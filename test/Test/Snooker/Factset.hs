{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -fno-warn-missing-signatures #-}
module Test.Snooker.Factset where

import           Control.Monad.Trans.Resource (runResourceT)

import           Crypto.Hash (Digest, MD5, digestFromByteString)

import           Data.Binary.Get (runGetOrFail)
import qualified Data.ByteString as B
import qualified Data.ByteString.Base16 as Base16
import qualified Data.ByteString.Lazy as L
import           Data.Conduit (($$+-), (=$=), newResumableSource)
import           Data.Conduit.Binary (sourceFile)
import qualified Data.Conduit.Combinators as Conduit
import qualified Data.Conduit.List as Conduit (consume)
import qualified Data.Text as T
import qualified Data.Vector as Boxed

import           Disorder.Core.IO

import           P

import           Snooker.Codec
import           Snooker.Conduit
import           Snooker.Data
import           Snooker.Writable

import           Test.QuickCheck (quickCheckAll, once, conjoin)
import           Test.QuickCheck ((.&&.), (===))
import           Test.QuickCheck.Property (property, counterexample, succeeded, failed)
import           Test.QuickCheck.Instances ()

import           Test.Snooker.Util

import           X.Control.Monad.Trans.Either (runEitherT)


fileSync :: Maybe (Digest MD5)
fileSync =
  digestFromByteString . fst $
    Base16.decode "b48b79e329914cd3d0ff793a86801dc7"

prop_read_header =
  once . testIO $ do
    lbs <- L.readFile "data/mackerel-2014-01-01"
    case runGetOrFail getHeader lbs of
      Left (_, _, msg) ->
        fail msg
      Right (_, _, hdr) ->
        return . conjoin $ [
            headerKeyType hdr === writableClass nullWritable
          , headerValueType hdr === writableClass bytesWritable
          , headerMetadata hdr === Metadata []
          , Just (headerSync hdr) === fileSync
          ]

prop_blocks =
  once . testEitherResource $ do

    let
      withFile f c = do
        (Metadata [], blocks) <-
          decodeBlocks nullWritable bytesWritable .
          newResumableSource $
          sourceFile "data/expression-2014-06-02"

        blocks $$+- Conduit.map f =$= c

    nrecords <- withFile blockCount Conduit.sum
    (nkeys :: Int) <- withFile blockKeys Conduit.lengthE
    values <- fmap Boxed.concat . withFile blockValues $ Conduit.consume

    return $
      nrecords === 20 .&&.
      nkeys === 20 .&&.
      Boxed.length values === 20 .&&.
      sum (fmap B.length values) === 657

prop_invalid_key_val =
  let
    tryDecode = do
      _ <-
        decodeBlocks bytesWritable nullWritable .
        newResumableSource $
        sourceFile "data/expression-2014-06-02"
      return ()

    check = \case
      Left (UnexpectedKeyType _ _) ->
        property succeeded
      Left err ->
        counterexample (show err) .
        counterexample (T.unpack $ renderSnookerError' err) $
        property failed
      Right () ->
        counterexample "Expected failure: UnexpectedKeyType" $
        property failed
  in
    testIO . fmap (once . check) . runResourceT $ runEitherT tryDecode

return []
tests =
  $quickCheckAll
