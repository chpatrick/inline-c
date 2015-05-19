{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}
import           Data.Monoid ((<>))
import qualified Data.Vector.Storable.Mutable as V
import           Foreign.C.Types
import qualified Language.Haskell.TH as TH
import qualified Test.Hspec as Hspec
import           Text.RawString.QQ (r)

import qualified Language.C.Inline as C
import qualified Language.C.Inline.Unsafe as CU
import qualified Language.C.Inline.Internal as C
import qualified Language.C.Inline.ContextSpec
import qualified Language.C.Inline.ParseSpec
import qualified Language.C.Types as C
import qualified Language.C.Types.ParseSpec

import           Dummy

C.context (C.baseCtx <> C.funCtx <> C.vecCtx)

C.include "<math.h>"
C.include "<stdio.h>"

C.verbatim [r|
int francescos_mul(int x, int y) {
  return x * y;
}
|]

foreign import ccall "francescos_mul" francescos_mul :: Int -> Int -> Int

main :: IO ()
main = Hspec.hspec $ do
  Hspec.describe "Language.C.Types.Parse" Language.C.Types.ParseSpec.spec
  Hspec.describe "Language.C.Inline.Context" Language.C.Inline.ContextSpec.spec
  Hspec.describe "Language.C.Inline.Parse" Language.C.Inline.ParseSpec.spec
  Hspec.describe "TH integration" $ do
    Hspec.it "inlineCode" $ do
      let c_add = $(C.inlineCode $ C.Code
            TH.Unsafe                   -- Call safety
            [t| Int -> Int -> Int |]    -- Call type
            "francescos_add"            -- Call name
            -- C Code
            [r| int francescos_add(int x, int y) { int z = x + y; return z; } |])
      c_add 3 4 `Hspec.shouldBe` 7
    Hspec.it "inlineItems" $ do
      let c_add3 = $(C.inlineItems
            TH.Unsafe
            [t| CInt -> CInt |]
            (C.quickCParser_ "int" C.parseType)
            [("x", C.quickCParser_ "int" C.parseType)]
            [r| return x + 3; |])
      c_add3 1 `Hspec.shouldBe` 1 + 3
    Hspec.it "inlineExp" $ do
      let x = $(C.inlineExp
            TH.Safe
            [t| CInt |]
            (C.quickCParser_ "int" C.parseType)
            []
            [r| 1 + 4 |])
      x `Hspec.shouldBe` 1 + 4
    Hspec.it "inlineCode" $ do
      francescos_mul 3 4 `Hspec.shouldBe` 12
    Hspec.it "exp" $ do
      let x = 3
      let y = 4
      z <- [C.exp| int{ $(int x) + $(int y) + 5 } |]
      z `Hspec.shouldBe` x + y + 5
    Hspec.it "pure" $ do
      let x = 2
      let y = 10
      let z = [C.pure| int{ $(int x) + 10 + $(int y) } |]
      z `Hspec.shouldBe` x + y + 10
    Hspec.it "unsafe exp" $ do
      let x = 2
      let y = 10
      z <- [CU.exp| int{ 7 + $(int x) + $(int y) } |]
      z `Hspec.shouldBe` x + y + 7
    Hspec.it "void exp" $ do
      [C.exp| void { printf("Hello\n") } |]
    Hspec.it "function pointer argument" $ do
      let ackermann m n
            | m == 0 = n + 1
            | m > 0 && n == 0 = ackermann (m - 1) 1
            | m > 0 && n > 0 = ackermann (m - 1) (ackermann m (n - 1))
            | otherwise = error "ackermann"
      ackermannPtr <- $(C.mkFunPtr [t| CInt -> CInt -> IO CInt |]) $ \m n -> return $ ackermann m n
      let x = 3
      let y = 4
      z <- [C.exp| int { $(int (*ackermannPtr)(int, int))($(int x), $(int y)) } |]
      z `Hspec.shouldBe` ackermann x y
    Hspec.it "function pointer result" $ do
      c_add <- [C.exp| int (*)(int, int) { &francescos_add } |]
      x <- $(C.peekFunPtr [t| CInt -> CInt -> IO CInt |]) c_add 1 2
      x `Hspec.shouldBe` 1 + 2
    Hspec.it "quick function pointer argument" $ do
      let ackermann m n
            | m == 0 = n + 1
            | m > 0 && n == 0 = ackermann (m - 1) 1
            | m > 0 && n > 0 = ackermann (m - 1) (ackermann m (n - 1))
            | otherwise = error "ackermann"
      let ackermann_ m n = return $ ackermann m n
      let x = 3
      let y = 4
      z <- [C.exp| int { $fun:(int (*ackermann_)(int, int))($(int x), $(int y)) } |]
      z `Hspec.shouldBe` ackermann x y
    Hspec.it "function pointer argument (pure)" $ do
      let ackermann m n
            | m == 0 = n + 1
            | m > 0 && n == 0 = ackermann (m - 1) 1
            | m > 0 && n > 0 = ackermann (m - 1) (ackermann m (n - 1))
            | otherwise = error "ackermann"
      ackermannPtr <- $(C.mkFunPtr [t| CInt -> CInt -> CInt |]) ackermann
      let x = 3
      let y = 4
      let z = [C.pure| int { $(int (*ackermannPtr)(int, int))($(int x), $(int y)) } |]
      z `Hspec.shouldBe` ackermann x y
    Hspec.it "quick function pointer argument (pure)" $ do
      let ackermann m n
            | m == 0 = n + 1
            | m > 0 && n == 0 = ackermann (m - 1) 1
            | m > 0 && n > 0 = ackermann (m - 1) (ackermann m (n - 1))
            | otherwise = error "ackermann"
      let x = 3
      let y = 4
      let z = [C.pure| int { $fun:(int (*ackermann)(int, int))($(int x), $(int y)) } |]
      z `Hspec.shouldBe` ackermann x y
    Hspec.it "test mkFunPtrFromName" $ do
      fun <- $(C.mkFunPtrFromName 'dummyFun)
      z <- [C.exp| double { $(double (*fun)(double))(3.0) } |]
      z' <- dummyFun 3.0
      z `Hspec.shouldBe` z'
    Hspec.it "vectors" $ do
      let n = 10
      vec <- V.replicate (fromIntegral n) 3
      sum' <- V.unsafeWith vec $ \ptr -> [C.block| int {
        int i;
        int x = 0;
        for (i = 0; i < $(int n); i++) {
          x += $(int *ptr)[i];
        }
        return x;
      } |]
      sum' `Hspec.shouldBe` 3 * 10
    Hspec.it "quick vectors" $ do
      vec <- V.replicate 10 3
      sum' <- [C.block| int {
        int i;
        int x = 0;
        for (i = 0; i < $vec-len:vec; i++) {
          x += $vec-ptr:(int *vec)[i];
        }
        return x;
      } |]
      sum' `Hspec.shouldBe` 3 * 10
