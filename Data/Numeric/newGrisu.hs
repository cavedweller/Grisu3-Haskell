import Data.Bits
import GHC.Int
import Data.Maybe
import Debug.Trace


grisu3 input    = printSign ++ generateString buffer (kappa + (-1*mk))
    where   v               =   if input < 0
                                then createDiyFp (fst $ decodeFloat(-input)) (fromIntegral (snd $ decodeFloat(input))) (True)
                                else createDiyFp (fst $ decodeFloat(input)) (fromIntegral (snd $ decodeFloat(input))) (False)
            w               =   normalize v
            boundryPlus     =   normalize $ createDiyFp (((f v) `shiftL` 1) + 1) ((e v) -1) (s v)
            mMinus          =   if (f v == kHiddenBit) && (e v /= kDenormalExponent)
                                then createDiyFp ((f v `shiftL` 2) - 1) (e v - 2) (s v)
                                else createDiyFp ((f v `shiftL` 1) - 1) (e v - 1) (s v)
                                    where   kHiddenBit = 2^52
                                            kSignificandSize = 52
                                            kExponentBias = 0x3FF + kSignificandSize
                                            kDenormalExponent = -kExponentBias + 1
            boundryMinus    =   createDiyFp ((f mMinus) `shiftL` fromIntegral (e mMinus - e boundryPlus)) (e boundryPlus) (s boundryPlus)
            fstAssert       =   (e boundryPlus) == (e w)
            (ten_mk, mk)    =  getCachedPower (fromIntegral (kMinimalTargetExp - ((fromIntegral (e w)) + kSignificandSize))) (fromIntegral (kMaximalTargetExp - ((fromIntegral (e w)) + kSignificandSize)))
            sndAssert       =   (kMinimalTargetExp <= ((e w) + (e ten_mk) + kSignificandSize)) && (kMaximalTargetExp >= ((e w) + (e ten_mk)  + kSignificandSize))
            scaled_w        = ten_mk * w
            trdAssert       = (e scaled_w) == (e boundryPlus + e ten_mk + kSignificandSize)
            scaledBoundryMinus = boundryMinus * ten_mk
            scaledBoundryPlus   = boundryPlus * ten_mk
            (buffer,kappa)  =   digitGen scaledBoundryMinus scaled_w scaledBoundryPlus
            kSignificandSize=   64
            kMinimalTargetExp  =   (-60)
            kMaximalTargetExp  =   (-32)
            printSign   =   if (s v == False)
                            then ""
                            else "-"
            
generateString (Just buffer@(x:xs)) decimalPoint
    | decimalPoint == (-1)                      = (foldl (\acc x -> acc ++ (show x)) ("0" ++ ".") buffer)
    | decimalPoint < (-1) || (decimalPoint > 6) = (foldl (\acc x -> acc ++ (show x)) ((show x) ++ ".") xs) ++ "e"++ (show decimalPoint)
    | otherwise                                 = (convert $ (fst $ splitAt (decimalPoint+1) buffer)) ++ "." ++ (convert $ (snd $ splitAt (decimalPoint+1) buffer))
        where   convert d   =   (foldl (\acc x -> acc ++ (show x)) ("") d)

getCachedPower  :: (Num a1, Ord a1, RealFrac a) => a -> a1 -> (DiyFp, Int)
getCachedPower min_exponent max_exponent = (cachedPower, decimalExponent)
    where   kQ  = 64
            kD_1_LOG2_10 = 0.30102999566398114
            k   = ceiling ((min_exponent + kQ  - 1) * kD_1_LOG2_10)
            foo = 348
            index = (((foo + k - 1) `div` kDecimalExponentDistance) + 1) 
            cachedPower  = fst $ powersOfTen !! index
            decimalExponent = snd $ powersOfTen !! index
            kDecimalExponentDistance = 8
            assert = (0 <= index && index < (length powersOfTen)) && (min_exponent <= fromIntegral (e cachedPower)) && (fromIntegral (e cachedPower) <= max_exponent) 

normalize :: DiyFp -> DiyFp
normalize v
            | f v                   == 0 = v
            | f v < (1 `shiftL` 55)      = normalize (createDiyFp ((f v) `shiftL` 8) ((e v) - 8) (s v))
            | (f v) .&. (2^63) == 0      = normalize (createDiyFp ((f v) `shiftL` 1) ((e v) - 1) (s v))
            | otherwise                  = v

digitGen :: DiyFp -> DiyFp -> DiyFp -> (Maybe [Integer], Int)
digitGen low fp high        = (buffer, kappa)
    where   too_low         = createDiyFp ((f low) - unit) (e low) (s low)
            too_high        = createDiyFp ((f high) + unit) (e high) (s high)
            unit            = 1
            shift           = fromIntegral (-1 * (e fp))
            unsafe_int      = too_high - too_low
            one             = createDiyFp (1 `shiftL` shift) (e fp) (False)
            integrals       = (f too_high) `shiftR` shift
            fractional      = (f too_high) .&. ((f one) -1)
            rest            = (integrals `shiftL` shift) + fractional
            (divisor,divExp)= powerTen integrals (kSignificandSize - shift)
            length          = 0
            (buffer,kappa)          = findInvariant (divExp + 1) [] length integrals divisor fractional (too_high - too_low) unit shift too_high fp one 
            assert          =(e low == e fp) && (e fp == e high) && (f low + 1 <= f high -1) && ((-60) <= e fp) && (e fp <= (-32))

findInvariant kappa buffer length integrals divisor fractional unsafe unit shift too_high w one
    |   (kappa > 0) =   if ((integrals `shiftL` shift) + fractional) < f unsafe
                        then trace (show buffer) (roundWeed (buffer ++ [(integrals `div` divisor)]) (length + 1) (f (too_high - w)) (f unsafe) (((integrals `mod` divisor) `shiftL` shift) + fractional) (divisor `shiftL` shift) unit, kappa - 1 + length)
                        else trace (show buffer)findInvariant (kappa - 1) (buffer ++  [(integrals `div` divisor)]) (length + 1) (integrals `mod` divisor) (divisor `div` 10) fractional unsafe unit shift too_high w one
    |   otherwise   =   if (((fractional*10) .&. ((f one) - 1))) < ((f unsafe)*10)
                        then trace (show buffer)(roundWeed (buffer ++ [((fractional * 10) `shiftR` shift)]) (length + 1) ((f (too_high - w)) * (unit*10)) ((f unsafe)*10) ((fractional*10) .&. ((f one) - 1)) (f one) (unit*10), kappa - 1 + length)
                        else trace (show buffer)findInvariant (kappa - 1) (buffer ++ [((fractional * 10) `shiftR` shift)]) (length + 1) (integrals) (divisor) ((fractional*10) .&. ((f one) - 1)) (createDiyFp (f unsafe *10) (e unsafe) False) (unit*10) shift too_high w one
    where hiddenAssert  =   ((e one) >= (-60)) && (fractional < (f one)) && ( (0xFFFFFFFFFFFFFFFF `div` 10) >= f one)



--smallPowerTen = map (10^) [0..10]


--biggestPowerTen number number_bits = (power,finExp)
--    where   assert = (number < (1 `shiftL` (number_bits + 1)))
--            exponentPlusOne = (((number_bits + 1) * 1223) `shiftR` 12) + 1
--            power = smallPowerTen !! finExp
--            finExp =    if (number < (smallPowerTen !! exponentPlusOne))
--                        then exponentPlusOne - 1
--                        else exponentPlusOne

kSignificandSize = 64

roundWeed buffer length distanceHigh unsafe rest tenkappa unit
    | ((rest < smallDistance) && (unsafe - rest >= tenkappa)) && (((rest + tenkappa) < smallDistance) || (smallDistance - rest >= rest + tenkappa - smallDistance)) =  roundWeed (init buffer ++ [(last buffer)-1]) length distanceHigh unsafe (rest + tenkappa) tenkappa unit
    | otherwise =   if  ((rest < bigDistance) && (unsafe - rest) >= tenkappa) && ((rest + tenkappa < bigDistance) || (bigDistance - rest) > (rest + tenkappa - bigDistance))
                    then Nothing
                    else    if ((2 * unit) <= rest) && (rest <= unsafe - (4 * unit))
                            then Just buffer
                            else Nothing
    where smallDistance = distanceHigh - unit 
          bigDistance = distanceHigh + unit 

--powerTen :: (Num a, Num t1, Num t2, Ord a) => t -> a -> (t1, t2)
powerTen number bits
    | (bits >= 30 && bits <= 32) = (1000000000,9)
    | bits >= 27 = (100000000,8)
    | bits >= 24 = (10000000,7)
    | bits >= 20 = (1000000,6)
    | bits >= 17 = (100000,5)
    | bits >= 14 = (10000,4)
    | bits >= 10 = (1000,3)
    | bits >= 7  = (100,2)
    | bits >= 4  = (10,1)
    | bits >= 1  = (1,0)
    | bits == 0  = (0,(-1))
    | otherwise  = (0,0)


createDiyFp :: Integer -> Int16 -> Bool -> DiyFp
createDiyFp x y z = DiyFp x y z

data DiyFp = DiyFp  { f :: Integer
                    , e :: Int16
                    , s :: Bool
                    }
    deriving(Show)

instance Num DiyFp where
    (+)     x y = addDiyFp x y
    (-)     x y = subDiyFp x y
    (*)     x y = mulDiyFp x y

addDiyFp    x y =   createDiyFp ((f x) + (f y)) (e x) (s x)
subDiyFp    x y =   createDiyFp ((f x) - (f y)) (e x) (s x)

mulDiyFp   x y = result
                where   a = (f x) `shiftR` 32
                        b = (f x) .&. 0xFFFFFFFF 
                        c = (f y) `shiftR` 32
                        d = (f y) .&. 0xFFFFFFFF
                        tmp = ((((b*d) `shiftR` 32) + ((a*d) .&. 0xFFFFFFFF) + ((b*c) .&. 0xFFFFFFFF)) + (1 `shiftL` 31))
                        newF = (a*c) + ((a*d) `shiftR` 32) + ((b*c) `shiftR` 32) + (tmp `shiftR` 32)
                        newE  = ((e x) + (e y) + 64) 
                        result = createDiyFp newF newE (s x)


firstPowerOfTen = -348
stepPowerOfTen  = 8

powersOfTen = [ 
	((DiyFp 0xfa8fd5a0081c0289 (-1220) False), (-348)), 
	((DiyFp 0xbaaee17fa23ebf76 (-1193) False), (-340)), 
	((DiyFp 0x8b16fb203055ac76 (-1166) False), (-332)), 
	((DiyFp 0xcf42894a5dce35ea (-1140) False), (-324)), 
	((DiyFp 0x9a6bb0aa55653b2d (-1113) False), (-316)), 
	((DiyFp 0xe61acf033d1a45df (-1087) False), (-308)), 
	((DiyFp 0xab70fe17c79ac6ca (-1060) False), (-300)), 
	((DiyFp 0xff77b1fcbebcdc4f (-1034) False), (-292)), 
	((DiyFp 0xbe5691ef416bd60c (-1007) False), (-284)), 
	((DiyFp 0x8dd01fad907ffc3c (-980) False), (-276)), 
	((DiyFp 0xd3515c2831559a83 (-954) False), (-268)), 
	((DiyFp 0x9d71ac8fada6c9b5 (-927) False), (-260)), 
	((DiyFp 0xea9c227723ee8bcb (-901) False), (-252)), 
	((DiyFp 0xaecc49914078536d (-874) False), (-244)), 
	((DiyFp 0x823c12795db6ce57 (-847) False), (-236)), 
	((DiyFp 0xc21094364dfb5637 (-821) False), (-228)), 
	((DiyFp 0x9096ea6f3848984f (-794) False), (-220)), 
	((DiyFp 0xd77485cb25823ac7 (-768) False), (-212)), 
	((DiyFp 0xa086cfcd97bf97f4 (-741) False), (-204)), 
	((DiyFp 0xef340a98172aace5 (-715) False), (-196)), 
	((DiyFp 0xb23867fb2a35b28e (-688) False), (-188)), 
	((DiyFp 0x84c8d4dfd2c63f3b (-661) False), (-180)), 
	((DiyFp 0xc5dd44271ad3cdba (-635) False), (-172)), 
	((DiyFp 0x936b9fcebb25c996 (-608) False), (-164)), 
	((DiyFp 0xdbac6c247d62a584 (-582) False), (-156)), 
	((DiyFp 0xa3ab66580d5fdaf6 (-555) False), (-148)), 
	((DiyFp 0xf3e2f893dec3f126 (-529) False), (-140)), 
	((DiyFp 0xb5b5ada8aaff80b8 (-502) False), (-132)), 
	((DiyFp 0x87625f056c7c4a8b (-475) False), (-124)), 
	((DiyFp 0xc9bcff6034c13053 (-449) False), (-116)), 
	((DiyFp 0x964e858c91ba2655 (-422) False), (-108)), 
	((DiyFp 0xdff9772470297ebd (-396) False), (-100)), 
	((DiyFp 0xa6dfbd9fb8e5b88f (-369) False), (-92)), 
	((DiyFp 0xf8a95fcf88747d94 (-343) False), (-84)), 
	((DiyFp 0xb94470938fa89bcf (-316) False), (-76)), 
	((DiyFp 0x8a08f0f8bf0f156b (-289) False), (-68)), 
	((DiyFp 0xcdb02555653131b6 (-263) False), (-60)), 
	((DiyFp 0x993fe2c6d07b7fac (-236) False), (-52)), 
	((DiyFp 0xe45c10c42a2b3b06 (-210) False), (-44)), 
	((DiyFp 0xaa242499697392d3 (-183) False), (-36)), 
	((DiyFp 0xfd87b5f28300ca0e (-157) False), (-28)), 
	((DiyFp 0xbce5086492111aeb (-130) False), (-20)), 
	((DiyFp 0x8cbccc096f5088cc (-103) False), (-12)), 
	((DiyFp 0xd1b71758e219652c (-77) False), (-4)),
	((DiyFp 0x9c40000000000000 (-50) False), (4)), 
	((DiyFp 0xe8d4a51000000000 (-24) False), (12)), 
	((DiyFp 0xad78ebc5ac620000 (3) False), (20)), 
	((DiyFp 0x813f3978f8940984 (30) False), (28)), 
	((DiyFp 0xc097ce7bc90715b3 (56) False), (36)), 
	((DiyFp 0x8f7e32ce7bea5c70 (83) False), (44)), 
	((DiyFp 0xd5d238a4abe98068 (109) False), (52)), 
	((DiyFp 0x9f4f2726179a2245 (136) False), (60)), 
	((DiyFp 0xed63a231d4c4fb27 (162) False), (68)), 
	((DiyFp 0xb0de65388cc8ada8 (189) False), (76)), 
	((DiyFp 0x83c7088e1aab65db (216) False), (84)), 
	((DiyFp 0xc45d1df942711d9a (242) False), (92)), 
	((DiyFp 0x924d692ca61be758 (269) False), (100)), 
	((DiyFp 0xda01ee641a708dea (295) False), (108)), 
	((DiyFp 0xa26da3999aef774a (322) False), (116)), 
	((DiyFp 0xf209787bb47d6b85 (348) False), (124)), 
	((DiyFp 0xb454e4a179dd1877 (375) False), (132)), 
	((DiyFp 0x865b86925b9bc5c2 (402) False), (140)), 
	((DiyFp 0xc83553c5c8965d3d (428) False), (148)), 
	((DiyFp 0x952ab45cfa97a0b3 (455) False), (156)), 
	((DiyFp 0xde469fbd99a05fe3 (481) False), (164)), 
	((DiyFp 0xa59bc234db398c25 (508) False), (172)), 
	((DiyFp 0xf6c69a72a3989f5c (534) False), (180)), 
	((DiyFp 0xb7dcbf5354e9bece (561) False), (188)), 
	((DiyFp 0x88fcf317f22241e2 (588) False), (196)), 
	((DiyFp 0xcc20ce9bd35c78a5 (614) False), (204)), 
	((DiyFp 0x98165af37b2153df (641) False), (212)), 
	((DiyFp 0xe2a0b5dc971f303a (667) False), (220)), 
	((DiyFp 0xa8d9d1535ce3b396 (694) False), (228)), 
	((DiyFp 0xfb9b7cd9a4a7443c (720) False), (236)), 
	((DiyFp 0xbb764c4ca7a44410 (747) False), (244)), 
	((DiyFp 0x8bab8eefb6409c1a (774) False), (252)), 
	((DiyFp 0xd01fef10a657842c (800) False), (260)), 
	((DiyFp 0x9b10a4e5e9913129 (827) False), (268)), 
	((DiyFp 0xe7109bfba19c0c9d (853) False), (276)), 
	((DiyFp 0xac2820d9623bf429 (880) False), (284)), 
	((DiyFp 0x80444b5e7aa7cf85 (907) False), (292)), 
	((DiyFp 0xbf21e44003acdd2d (933) False), (300)), 
	((DiyFp 0x8e679c2f5e44ff8f (960) False), (308)), 
	((DiyFp 0xd433179d9c8cb841 (986) False), (316)), 
	((DiyFp 0x9e19db92b4e31ba9 (1013) False), (324)), 
	((DiyFp 0xeb96bf6ebadf77d9 (1039) False), (332)), 
	((DiyFp 0xaf87023b9bf0ee6b (1066) False), (340))]

