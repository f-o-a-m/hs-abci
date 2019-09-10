{-# OPTIONS_GHC -fno-warn-orphans #-}
module Tendermint.SDK.StoreExample.Instances () where

import           Test.QuickCheck                   (getPrintableString)
import           Test.QuickCheck.Arbitrary         (Arbitrary, arbitrary)
import           Test.QuickCheck.Arbitrary.Generic (genericArbitrary)
import           Test.QuickCheck.Instances         ()

import           Tendermint.SDK.StoreExample

instance Arbitrary Buyer where arbitrary = genericArbitrary
instance Arbitrary BuyerKey where arbitrary = BuyerKey . getPrintableString <$> arbitrary
instance Arbitrary Owner where arbitrary = genericArbitrary
instance Arbitrary OwnerKey where arbitrary = OwnerKey . getPrintableString <$> arbitrary
instance Arbitrary Lab where arbitrary = genericArbitrary
instance Arbitrary LabKey where arbitrary = LabKey . getPrintableString <$> arbitrary
instance Arbitrary Hound where arbitrary = genericArbitrary
instance Arbitrary HoundKey where arbitrary = HoundKey . getPrintableString <$> arbitrary