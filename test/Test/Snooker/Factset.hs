{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -fno-warn-missing-signatures #-}
module Test.Snooker.Factset where

import           Control.Monad.Trans.Resource (ResourceT, runResourceT)

import           Crypto.Hash (Digest, MD5, digestFromByteString)

import           Data.Binary.Get (runGetOrFail)
import qualified Data.ByteString.Base16 as Base16
import qualified Data.ByteString.Lazy as L
import           Data.Conduit (($$+-), newResumableSource)
import           Data.Conduit.Binary (sourceFile)
import qualified Data.Conduit.List as Conduit
import qualified Data.Text as T

import           Disorder.Core.IO

import           P

import           Snooker.Codec
import           Snooker.Conduit
import           Snooker.Data

import           System.IO (IO)

import           Test.QuickCheck (Property, quickCheckAll, once, conjoin, (===))
import           Test.QuickCheck.Property (counterexample, failed)
import           Test.QuickCheck.Instances ()

import           X.Control.Monad.Trans.Either (EitherT, runEitherT)


fileSync :: Maybe (Digest MD5)
fileSync =
  digestFromByteString . fst $
    Base16.decode "b48b79e329914cd3d0ff793a86801dc7"

nullWritable :: ClassName
nullWritable =
  ClassName "org.apache.hadoop.io.NullWritable"

bytesWritable :: ClassName
bytesWritable =
  ClassName "org.apache.hadoop.io.BytesWritable"

prop_read_header =
  once . testIO $ do
    lbs <- L.readFile "data/mackerel-2014-01-01"
    case runGetOrFail getHeader lbs of
      Left (_, _, msg) ->
        fail msg
      Right (_, _, hdr) ->
        return . conjoin $ [
            headerKeyType hdr === nullWritable
          , headerValueType hdr === bytesWritable
          , headerMetadata hdr === []
          , Just (headerSync hdr) === fileSync
          ]

testEitherResource :: EitherT SnookerError (ResourceT IO) Property -> Property
testEitherResource =
  let
    ensureRight = \case
      Left err ->
        counterexample (T.unpack $ renderSnookerError err) $
        failed
      Right prop ->
        prop
  in
    testIO . runResourceT . fmap ensureRight . runEitherT

prop_compressed_blocks =
  once . testEitherResource $ do
    let
      file = newResumableSource $ sourceFile "data/expression-2014-06-02"
    (_, blocks) <- decodeCompressedBlocks file
    records <- blocks $$+- Conduit.fold (\n cb -> compressedCount cb + n) 0
    return $
      records === 20

return []
tests =
  $quickCheckAll
