{-# OPTIONS_GHC -cpp -fglasgow-exts -fno-warn-orphans #-}
--
-- Module      : Data.ByteString.Fusion
-- License     : BSD-style
-- Maintainer  : dons@cse.unsw.edu.au
-- Stability   : experimental
-- Portability : portable, requires ffi and cpp
-- Tested with : GHC 6.4.1 and Hugs March 2005
-- 

--
-- | Functional array fusion for ByteStrings. 
--
-- From the Data Parallel Haskell project, 
-- >    http://www.cse.unsw.edu.au/~chak/project/dph/
--
--
module Data.ByteString.Fusion (

    -- * Fusion utilities
    loopU, fuseEFL,
    NoAcc(NoAcc), loopArr, loopAcc, loopSndAcc, unSP,
    mapEFL, filterEFL, foldEFL, foldEFL', scanEFL, mapAccumEFL, mapIndexEFL,

    -- * Strict pairs and sums
    PairS(..), MaybeS(..)

  ) where

import Data.ByteString.Base

import Foreign.ForeignPtr
import Foreign.Ptr
import Foreign.Storable         (Storable(..))

import Data.Word                (Word8)

-- -----------------------------------------------------------------------------
--
-- Useful macros, until we have bang patterns
--

#define STRICT1(f) f a | a `seq` False = undefined
#define STRICT2(f) f a b | a `seq` b `seq` False = undefined
#define STRICT3(f) f a b c | a `seq` b `seq` c `seq` False = undefined
#define STRICT4(f) f a b c d | a `seq` b `seq` c `seq` d `seq` False = undefined
#define STRICT5(f) f a b c d e | a `seq` b `seq` c `seq` d `seq` e `seq` False = undefined

infixl 2 :*:

-- |Strict pair
data PairS a b = !a :*: !b deriving (Eq,Ord,Show)

-- |Strict Maybe
data MaybeS a = NothingS | JustS !a

-- |Data type for accumulators which can be ignored. The rewrite rules rely on
-- the fact that no bottoms of this type are ever constructed; hence, we can
-- assume @(_ :: NoAcc) `seq` x = x@.
--
data NoAcc = NoAcc

-- |Type of loop functions
type AccEFL acc = acc -> Word8 -> (PairS acc (MaybeS Word8))
--type NoAccEFL   =        Word8 ->             MaybeS Word8
--type MapEFL     =        Word8 ->                    Word8
--type FilterEFL  =        Word8 ->             Bool

infixr 9 `fuseEFL`

-- |Fuse to flat loop functions
fuseEFL :: AccEFL acc1 -> AccEFL acc2 -> AccEFL (PairS acc1 acc2)
fuseEFL f g (acc1 :*: acc2) e1 =
    case f acc1 e1 of
        acc1' :*: NothingS -> (acc1' :*: acc2) :*: NothingS
        acc1' :*: JustS e2 ->
            case g acc2 e2 of
                acc2' :*: res -> (acc1' :*: acc2') :*: res
#if defined(__GLASGOW_HASKELL__)
{-# INLINE [1] fuseEFL #-}
#endif

-- | Special forms of loop arguments
--
-- * These are common special cases for the three function arguments of gen
--   and loop; we give them special names to make it easier to trigger RULES
--   applying in the special cases represented by these arguments.  The
--   "INLINE [1]" makes sure that these functions are only inlined in the last
--   two simplifier phases.
--
-- * In the case where the accumulator is not needed, it is better to always
--   explicitly return a value `()', rather than just copy the input to the
--   output, as the former gives GHC better local information.
-- 

-- | Element function expressing a mapping only
mapEFL :: (Word8 -> Word8) -> AccEFL NoAcc
mapEFL f = \_ e -> (NoAcc :*: (JustS $ f e))
#if defined(__GLASGOW_HASKELL__)
{-# INLINE [1] mapEFL #-}
#endif

-- | Element function implementing a filter function only
filterEFL :: (Word8 -> Bool) -> AccEFL NoAcc
filterEFL p = \_ e -> if p e then (NoAcc :*: JustS e) else (NoAcc :*: NothingS)
#if defined(__GLASGOW_HASKELL__)
{-# INLINE [1] filterEFL #-}
#endif

-- |Element function expressing a reduction only
foldEFL :: (acc -> Word8 -> acc) -> AccEFL acc
foldEFL f = \a e -> (f a e :*: NothingS)
#if defined(__GLASGOW_HASKELL__)
{-# INLINE [1] foldEFL #-}
#endif

-- | A strict foldEFL.
foldEFL' :: (acc -> Word8 -> acc) -> AccEFL acc
foldEFL' f = \a e -> let a' = f a e in a' `seq` (a' :*: NothingS)
#if defined(__GLASGOW_HASKELL__)
{-# INLINE [1] foldEFL' #-}
#endif

-- | Element function expressing a prefix reduction only
--
scanEFL :: (Word8 -> Word8 -> Word8) -> AccEFL Word8
scanEFL f = \a e -> (f a e :*: JustS a)
#if defined(__GLASGOW_HASKELL__)
{-# INLINE [1] scanEFL #-}
#endif

-- | Element function implementing a map and fold
--
mapAccumEFL :: (acc -> Word8 -> (acc, Word8)) -> AccEFL acc
mapAccumEFL f = \a e -> case f a e of (a', e') -> (a' :*: JustS e')
#if defined(__GLASGOW_HASKELL__)
{-# INLINE [1] mapAccumEFL #-}
#endif

-- | Element function implementing a map with index
--
mapIndexEFL :: (Int -> Word8 -> Word8) -> AccEFL Int
mapIndexEFL f = \i e -> let i' = i+1 in i' `seq` (i' :*: JustS (f i e))
#if defined(__GLASGOW_HASKELL__)
{-# INLINE [1] mapIndexEFL #-}
#endif

-- | Projection functions that are fusion friendly (as in, we determine when
-- they are inlined)
loopArr :: (PairS acc arr) -> arr
loopArr (_ :*: arr) = arr
#if defined(__GLASGOW_HASKELL__)
{-# INLINE [1] loopArr #-}
#endif

loopAcc :: (PairS acc arr) -> acc
loopAcc (acc :*: _) = acc
#if defined(__GLASGOW_HASKELL__)
{-# INLINE [1] loopAcc #-}
#endif

loopSndAcc :: (PairS (PairS acc1 acc2) arr) -> (PairS acc2 arr)
loopSndAcc ((_ :*: acc) :*: arr) = (acc :*: arr)
#if defined(__GLASGOW_HASKELL__)
{-# INLINE [1] loopSndAcc #-}
#endif

unSP :: (PairS acc arr) -> (acc, arr)
unSP (acc :*: arr) = (acc, arr)
#if defined(__GLASGOW_HASKELL__)
{-# INLINE [1] unSP #-}
#endif

------------------------------------------------------------------------
--
-- Loop combinator and fusion rules for flat arrays
-- |Iteration over over ByteStrings

-- | Iteration over over ByteStrings
loopU :: AccEFL acc                 -- ^ mapping & folding, once per elem
      -> acc                        -- ^ initial acc value
      -> ByteString                 -- ^ input ByteString
      -> (PairS acc ByteString)

loopU f start (PS z s i) = inlinePerformIO $ withForeignPtr z $ \a -> do
    fp          <- mallocByteString i
    (ptr,n,acc) <- withForeignPtr fp $ \p -> do
        (acc :*: i') <- go (a `plusPtr` s) p start
        if i' == i
            then return (fp,i',acc)                 -- no realloc for map
            else do fp_ <- mallocByteString i'      -- realloc
                    withForeignPtr fp_ $ \p' -> memcpy p' p (fromIntegral i')
                    return (fp_,i',acc)

    return (acc :*: PS ptr 0 n)
  where
    go p ma = trans 0 0
        where
            STRICT3(trans)
            trans a_off ma_off acc
                | a_off >= i = return (acc :*: ma_off)
                | otherwise  = do
                    x <- peekByteOff p a_off
                    let (acc' :*: oe) = f acc x
                    ma_off' <- case oe of
                        NothingS -> return ma_off
                        JustS e  -> do pokeByteOff ma ma_off e
                                       return $ ma_off + 1
                    trans (a_off+1) ma_off' acc'

#if defined(__GLASGOW_HASKELL__)
{-# INLINE [1] loopU #-}
#endif

{-# RULES

"loop/loop fusion!" forall em1 em2 start1 start2 arr.
  loopU em2 start2 (loopArr (loopU em1 start1 arr)) =
    loopSndAcc (loopU (em1 `fuseEFL` em2) (start1 :*: start2) arr)

"loopArr/loopSndAcc" forall x.
  loopArr (loopSndAcc x) = loopArr x

"seq/NoAcc" forall (u::NoAcc) e.
  u `seq` e = e

  #-}


{-

Alternate experimental formulation of loopU which partitions it into
an allocating wrapper and an imperitive array-mutating loop.

The point in doing this split is that we might be able to fuse multiple
loops into a single wrapper. This would save reallocating another buffer.
It should also give better cache locality by reusing the buffer.

However, just at the moment we're having troubles with ghc RULES.
Try this module as a test case:

> module Fuse where
> import Data.Word (Word8)
> import qualified Data.ByteString as B

> f :: Word8 -> Word8
> f x = x
> {-# NOINLINE f #-}

> foo :: B.ByteString -> B.ByteString
> foo = B.map f . B.map f . B.map f . B.map f

and compile it using:
> ghc -c fuse.hs -O -ddump-simpl-stats

We get:
9 RuleFired
    3 loop/loop wrapper elimination
    3 loopArr/loopSndAcc
    3 up/up loop fusion

which is great, but if you trace which phases these RULES are firing in the
picture becomes less joyous.
> ghc -c fuse.hs -O -ddump-simpl-stats -ddump-simpl-iterations | less

==================== Simplifier phase 2, iteration 2 out of 4 ====================
7 RuleFired
    3 loop/loop wrapper elimination
    3 loopArr/loopSndAcc
    1 up/up loop fusion

Oh no! We're not getting all the up/up loop fusions in the first go.

==================== Simplifier phase 2, iteration 3 out of 4 ====================
1 RuleFired
    1 up/up loop fusion

==================== Simplifier phase 2, iteration 4 out of 4 ====================
1 RuleFired
    1 up/up loop fusion

Now because this is a small test case we end up with all the loop fusion
happening in phase 2. However for longer piplines of map . filer . etc
we would end up with those leaking into the next phase which is bad. It's
bad because in the next phase we want to start inlining other stuff and doing
that other inlining would then prevent the fusion rule from firing. We need
to get the loop fusion rules to happen all in one go as happens with the
wrapper elimination (by using the helper rule loopArr/loopSndAcc).

It's not clear to me at the moment why the loop fusion rules are not firing.
I would expect that each one would expose the next in the pipeline and so
by exhaustively applying the rule we would get them all in one iteration of
the simplifier. In the wrapper elimination we need the helper rule to be able
to do it all in one iteration. So perhaps all we need is to find a similar
helper rule. However from looking at the core I can't see an obvious
transformation that would expose an opportunity for the rule to match. Indeed
I can't actually see why the rule doesn't match at the moment. Reading core
is hard! :-) The expression is rather larger than I expected:

Remember our function 'foo':

foo = B.map f . B.map f . B.map f . B.map f

Here's what the core looks like after the wrapper elimination and one loop
fusion. We can see that there are two instances of sequenceLoops left. We
want to know why these didn't match the loop fusion rule:

"up/up loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doUpLoop f1 acc1) (doUpLoop f2 acc2) =
    doUpLoop (f1 `fuseAccAccEFL` f2) (acc1 :*: acc2)

anyway, here's the core (slightly tidied up to shorten long names etc)

Fuse.foo =
  \ (x :: ByteString) ->
     loopArr
       @ (PairS (PairS (PairS NoAcc NoAcc) NoAcc) NoAcc)
       @ ByteString
       (loopWrapper
          @ (PairS (PairS (PairS NoAcc NoAcc) NoAcc) NoAcc)
          (sequenceLoops
             @ (PairS (PairS NoAcc NoAcc) NoAcc)
             @ NoAcc
             (sequenceLoops
                @ (PairS NoAcc NoAcc)
                @ NoAcc
                (let {
                   f1 :: NoAcc -> Word8 -> PairS NoAcc (MaybeS Word8)
                   [Arity 2]
                   f1 = mapEFL Fuse.f } in
                 let {
                   f2 :: NoAcc -> Word8 -> PairS NoAcc (MaybeS Word8)
                   [Arity 2]
                   f2 = mapEFL Fuse.f
                 } in
                   doUpLoop
                     @ (PairS NoAcc NoAcc)
                     (fuseAccAccEFL
                        @ NoAcc @ NoAcc f1 f2)
                     (:*:
                        @ NoAcc
                        @ NoAcc
                        NoAcc
                        NoAcc))
                (doUpLoop
                   @ NoAcc
                   (mapEFL Fuse.f)
                   NoAcc))
             (doUpLoop
                @ NoAcc
                (mapEFL Fuse.f)
                NoAcc))
          x)

So here's the thing then, it looks like the rule doesn't match because
it is not exactly of the form:

sequenceLoops (doUpLoop f1 acc1) (doUpLoop f2 acc2)

it's actually of the form

sequenceLoops (doUpLoop f1 acc1)
              (let f2 = ...
                   f3 = ...
                in doUpLoop (fuseAccAccEFL f2 f3) acc2)

but this is still an ok form we just need to have the rule matching
look at the body of the let.

loopUp :: AccEFL acc -> acc -> ByteString -> PairS acc ByteString
loopUp f a arr = loopWrapper (doUpLoop f a) arr

loopDown :: AccEFL acc -> acc -> ByteString -> PairS acc ByteString
loopDown f a arr = loopWrapper (doDownLoop f a) arr

loopNoAcc :: NoAccEFL -> ByteString -> PairS NoAcc ByteString
loopNoAcc f arr = loopWrapper (doNoAccLoop f NoAcc) arr

loopMap :: MapEFL -> ByteString -> PairS NoAcc ByteString
loopMap f arr = loopWrapper (doMapLoop f NoAcc) arr

loopFilter :: FilterEFL -> ByteString -> PairS NoAcc ByteString
loopFilter f arr = loopWrapper (doFilterLoop f NoAcc) arr

-- The type of imperitive loops that fill in a destination array by
-- reading a source array. They may not fill in the whole of the dest
-- array if the loop is behaving as a filter, this is why we return
-- the length that was filled in. The loop may also accumulate some
-- value as it loops over the source array.
--
type ImperativeLoop acc =
    Ptr Word8          -- pointer to the start of the source byte array
 -> Ptr Word8          -- pointer to ther start of the destination byte array
 -> Int                -- length of the source byte array
 -> IO (PairS acc Int) -- result and length of destination that was filled

loopWrapper :: ImperativeLoop acc -> ByteString -> PairS acc ByteString
loopWrapper body (PS srcFPtr srcOffset srcLen) =
  inlinePerformIO $ withForeignPtr srcFPtr $ \srcPtr -> do
    destFPtr <- mallocByteString srcLen
    withForeignPtr destFPtr $ \destPtr -> do
      (acc :*: destLen) <- body (srcPtr `plusPtr` srcOffset) destPtr srcLen
      if destLen == srcLen
          then return (acc :*: PS destFPtr 0 destLen)   -- no realloc for map
          else do destFPtr' <- mallocByteString destLen -- realloc
                  withForeignPtr destFPtr' $ \destPtr' ->
                    memcpy destPtr' destPtr (fromIntegral destLen)
                  return (acc :*: PS destFPtr' 0 destLen)

doUpLoop :: AccEFL acc -> acc -> ImperativeLoop acc
doUpLoop f acc0 src dest len = loop 0 0 acc0
  where STRICT3(loop)
        loop src_off dest_off acc
            | src_off >= len = return (acc :*: dest_off)
            | otherwise      = do
                x <- peekByteOff src src_off
                case f acc x of
                  (acc' :*: NothingS) -> loop (src_off+1) dest_off acc'
                  (acc' :*: JustS x') -> pokeByteOff dest dest_off x'
                                      >> loop (src_off+1) (dest_off+1) acc'

doDownLoop :: AccEFL acc -> acc -> ImperativeLoop acc
doDownLoop f acc0 src dest len = loop (len-1) (len-1) acc0
  where STRICT3(loop)
        loop src_off dest_off acc
            | src_off <  0 = return (acc :*: dest_off)
            | otherwise    = do
                x <- peekByteOff src src_off
                case f acc x of
                  (acc' :*: NothingS) -> loop (src_off-1) dest_off acc'
                  (acc' :*: JustS x') -> pokeByteOff dest dest_off x'
                                      >> loop (src_off-1) (dest_off-1) acc'

doNoAccLoop :: NoAccEFL -> noAcc -> ImperativeLoop noAcc
doNoAccLoop f noAcc src dest len = loop 0 0
  where STRICT2(loop)
        loop src_off dest_off
            | src_off >= len = return (noAcc :*: dest_off)
            | otherwise      = do
                x <- peekByteOff src src_off
                case f x of
                  NothingS -> loop (src_off+1) dest_off
                  JustS x' -> pokeByteOff dest dest_off x'
                           >> loop (src_off+1) (dest_off+1)

doMapLoop :: MapEFL -> noAcc -> ImperativeLoop noAcc
doMapLoop f noAcc src dest len = loop 0 0
  where STRICT2(loop)
        loop src_off dest_off
            | src_off >= len = return (noAcc :*: len)
            | otherwise      = do
                x <- peekByteOff src src_off
                pokeByteOff dest dest_off (f x)
                loop (src_off+1) (dest_off+1)

doFilterLoop :: FilterEFL -> noAcc -> ImperativeLoop noAcc
doFilterLoop f noAcc src dest len = loop 0 0
  where STRICT2(loop)
        loop src_off dest_off
            | src_off >= len = return (noAcc :*: dest_off)
            | otherwise      = do
                x <- peekByteOff src src_off
                if f x
                  then pokeByteOff dest dest_off x
                    >> loop (src_off+1) (dest_off+1)
                  else loop (src_off+1) dest_off

-- run two loops in sequence,
-- think of it as: loop1 >> loop2
sequenceLoops :: ImperativeLoop acc -> ImperativeLoop acc' -> ImperativeLoop (PairS acc acc')
sequenceLoops loop1 loop2 src dest len = do
  (acc  :*: len')  <- loop1 src  dest len
  (acc' :*: len'') <- loop2 dest dest len'
  return ((acc  :*: acc') :*: len'')
  -- note that we are using src == dest for the second loop
  -- yes, we are mutating the dest array in-place!

  -- TODO: prove that this is associative! (I think it is)
  -- since we can't be sure how the RULES will combine loops.

{-# INLINE loopUp #-}
{-# INLINE loopDown #-}
{-# INLINE loopNoAcc #-}
{-# INLINE loopMap #-}
{-# INLINE loopFilter #-}

#if defined(__GLASGOW_HASKELL__)

{-# NOINLINE  doUpLoop     #-}
{-# NOINLINE  doDownLoop   #-}
{-# NOINLINE  doNoAccLoop  #-}
{-# NOINLINE  doMapLoop    #-}
{-# NOINLINE  doFilterLoop #-}

{-# NOINLINE  loopWrapper   #-}
{-# NOINLINE  sequenceLoops #-}
#endif

{-# RULES

"loop/loop wrapper elimination" forall loop1 loop2 arr.
  loopWrapper loop2 (loopArr (loopWrapper loop1 arr)) =
    loopSndAcc (loopWrapper (sequenceLoops loop1 loop2) arr)


"up/up loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doUpLoop f1 acc1) (doUpLoop f2 acc2) =
    doUpLoop (f1 `fuseAccAccEFL` f2) (acc1 :*: acc2)

"down/down loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doDownLoop f1 acc1) (doDownLoop f2 acc2) =
    doDownLoop (f1 `fuseAccAccEFL` f2) (acc1 :*: acc2)

"noAcc/noAcc loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doNoAccLoop f1 acc1) (doNoAccLoop f2 acc2) =
    doNoAccLoop (f1 `fuseNoAccNoAccEFL` f2) (acc1 :*: acc2)


"noAcc/up loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doNoAccLoop f1 acc1) (doUpLoop f2 acc2) =
    doUpLoop (f1 `fuseNoAccAccEFL` f2) (acc1 :*: acc2)

"up/noAcc loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doUpLoop f1 acc1) (doNoAccLoop f2 acc2) =
    doUpLoop (f1 `fuseAccNoAccEFL` f2) (acc1 :*: acc2)

"noAcc/down loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doNoAccLoop f1 acc1) (doDownLoop f2 acc2) =
    doDownLoop (f1 `fuseNoAccAccEFL` f2) (acc1 :*: acc2)

"down/noAcc loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doDownLoop f1 acc1) (doNoAccLoop f2 acc2) =
    doDownLoop (f1 `fuseAccNoAccEFL` f2) (acc1 :*: acc2)


"map/map loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doMapLoop f1 acc1) (doMapLoop f2 acc2) =
    doMapLoop (f2 `fuseMapMapEFL` f1) (acc1 :*: acc2)

"filter/filter loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doFilterLoop f1 acc1) (doFilterLoop f2 acc2) =
    doFilterLoop (f1 `fuseFilterFilterEFL` f2) (acc1 :*: acc2)

"map/filter loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doMapLoop f1 acc1) (doFilterLoop f2 acc2) =
    doNoAccLoop (f1 `fuseMapFilterEFL` f2) (acc1 :*: acc2)

"filter/map loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doFilterLoop f1 acc1) (doMapLoop f2 acc2) =
    doNoAccLoop (f1 `fuseFilterMapEFL` f2) (acc1 :*: acc2)


"map/noAcc loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doMapLoop f1 acc1) (doNoAccLoop f2 acc2) =
    doNoAccLoop (f1 `fuseMapNoAccEFL` f2) (acc1 :*: acc2)

"noAcc/map loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doNoAccLoop f1 acc1) (doMapLoop f2 acc2) =
    doNoAccLoop (f1 `fuseNoAccMapEFL` f2) (acc1 :*: acc2)

"map/up loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doMapLoop f1 acc1) (doUpLoop f2 acc2) =
    doUpLoop (f1 `fuseMapAccEFL` f2) (acc1 :*: acc2)

"up/map loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doUpLoop f1 acc1) (doMapLoop f2 acc2) =
    doUpLoop (f1 `fuseAccMapEFL` f2) (acc1 :*: acc2)

"map/down fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doMapLoop f1 acc1) (doDownLoop f2 acc2) =
    doDownLoop (f1 `fuseMapAccEFL` f2) (acc1 :*: acc2)

"down/map loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doDownLoop f1 acc1) (doMapLoop f2 acc2) =
    doDownLoop (f1 `fuseAccMapEFL` f2) (acc1 :*: acc2)


"filter/noAcc loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doFilterLoop f1 acc1) (doNoAccLoop f2 acc2) =
    doNoAccLoop (f1 `fuseFilterNoAccEFL` f2) (acc1 :*: acc2)

"noAcc/filter loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doNoAccLoop f1 acc1) (doFilterLoop f2 acc2) =
    doNoAccLoop (f1 `fuseNoAccFilterEFL` f2) (acc1 :*: acc2)

"filter/up loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doFilterLoop f1 acc1) (doUpLoop f2 acc2) =
    doUpLoop (f1 `fuseFilterAccEFL` f2) (acc1 :*: acc2)

"up/filter loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doUpLoop f1 acc1) (doFilterLoop f2 acc2) =
    doUpLoop (f1 `fuseAccFilterEFL` f2) (acc1 :*: acc2)

"filter/down fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doFilterLoop f1 acc1) (doDownLoop f2 acc2) =
    doDownLoop (f1 `fuseFilterAccEFL` f2) (acc1 :*: acc2)

"down/filter loop fusion" forall f1 f2 acc1 acc2.
  sequenceLoops (doDownLoop f1 acc1) (doFilterLoop f2 acc2) =
    doDownLoop (f1 `fuseAccFilterEFL` f2) (acc1 :*: acc2)


"loopArr/loopSndAcc" forall x.
  loopArr (loopSndAcc x) = loopArr x

"seq/NoAcc" forall (u::NoAcc) e.
  u `seq` e = e

  #-}

{-

up = up loop
down = down loop
noAcc = noAcc undirectional loop
map = map special case
filter = filter special case

heirarchy:
  up     down
   ^     ^
    \   /
    noAcc
     ^ ^
    /   \
 map     filter

each is a special case of the things above

so we get rules that combine things on the same level
and rules that combine things on different levels
to get something on the higher level

so all the cases:
up/up         --> up     fuseAccAccEFL
down/down     --> down   fuseAccAccEFL
noAcc/noAcc   --> noAcc  fuseNoAccNoAccEFL

noAcc/up      --> up     fuseNoAccAccEFL
up/noAcc      --> up     fuseAccNoAccEFL
noAcc/down    --> down   fuseNoAccAccEFL
down/noAcc    --> down   fuseAccNoAccEFL

and if we do the map, filter special cases then it adds a load more:

map/map       --> map    fuseMapMapEFL
filter/filter --> filter fuseFilterFilterEFL

map/filter    --> noAcc  fuseMapFilterEFL
filter/map    --> noAcc  fuseFilterMapEFL

map/noAcc     --> noAcc  fuseMapNoAccEFL
noAcc/map     --> noAcc  fuseNoAccMapEFL

map/up        --> up     fuseMapAccEFL
up/map        --> up     fuseAccMapEFL

map/down      --> down   fuseMapAccEFL
down/map      --> down   fuseAccMapEFL

filter/noAcc  --> noAcc  fuseNoAccFilterEFL
noAcc/filter  --> noAcc  fuseFilterNoAccEFL

filter/up     --> up     fuseFilterAccEFL
up/filter     --> up     fuseAccFilterEFL

filter/down   --> down   fuseFilterAccEFL
down/filter   --> down   fuseAccFilterEFL
-}

fuseAccAccEFL :: AccEFL acc1 -> AccEFL acc2 -> AccEFL (PairS acc1 acc2)
fuseAccAccEFL f g (acc1 :*: acc2) e1 =
  case f acc1 e1 of
    acc1' :*: NothingS -> (acc1' :*: acc2) :*: NothingS
    acc1' :*: JustS e2 ->
      case g acc2 e2 of
        acc2' :*: res -> (acc1' :*: acc2') :*: res
{-# NOINLINE fuseAccAccEFL #-}


fuseAccNoAccEFL :: AccEFL acc -> NoAccEFL -> AccEFL (PairS acc noAcc)
fuseAccNoAccEFL f g (acc :*: noAcc) e1 =
  case f acc e1 of
    acc' :*: NothingS -> (acc' :*: noAcc) :*: NothingS
    acc' :*: JustS e2 -> (acc' :*: noAcc) :*: g e2

fuseNoAccAccEFL :: NoAccEFL -> AccEFL acc -> AccEFL (PairS noAcc acc)
fuseNoAccAccEFL f g (noAcc :*: acc) e1 =
  case f e1 of
    NothingS -> (noAcc :*: acc) :*: NothingS
    JustS e2 ->
      case g acc e2 of
        acc' :*: res -> (noAcc :*: acc') :*: res

fuseNoAccNoAccEFL :: NoAccEFL -> NoAccEFL -> NoAccEFL
fuseNoAccNoAccEFL f g e1 =
  case f e1 of
    NothingS -> NothingS
    JustS e2 -> g e2

fuseMapAccEFL :: MapEFL -> AccEFL acc -> AccEFL (PairS noAcc acc)
fuseMapAccEFL f g (noAcc :*: acc) e1 = 
  case g acc (f e1) of
    (acc' :*: res) -> (noAcc :*: acc') :*: res

fuseAccMapEFL :: AccEFL acc -> MapEFL -> AccEFL (PairS acc noAcc)
fuseAccMapEFL f g (acc :*: noAcc) e1 =
    case f acc e1 of
        (acc' :*: NothingS) -> (acc' :*: noAcc) :*: NothingS
        (acc' :*: JustS e2) -> (acc' :*: noAcc) :*: JustS (g e2)

fuseMapNoAccEFL :: MapEFL -> NoAccEFL -> NoAccEFL
fuseMapNoAccEFL f g e1 = g (f e1)

fuseNoAccMapEFL :: NoAccEFL -> MapEFL -> NoAccEFL
fuseNoAccMapEFL f g e1 =
    case f e1 of
        NothingS -> NothingS
        JustS e2 -> JustS (g e2)

fuseMapMapEFL :: MapEFL -> MapEFL -> MapEFL
fuseMapMapEFL f g e1 = g (f e1)

fuseAccFilterEFL :: AccEFL acc -> FilterEFL -> AccEFL (PairS acc noAcc)
fuseAccFilterEFL f g (acc :*: noAcc) e1 =
  case f acc e1 of
    acc' :*: NothingS -> (acc' :*: noAcc) :*: NothingS
    acc' :*: JustS e2 ->
      case g e2 of
        False -> (acc' :*: noAcc) :*: NothingS
        True  -> (acc' :*: noAcc) :*: JustS e2

fuseFilterAccEFL :: FilterEFL -> AccEFL acc -> AccEFL (PairS noAcc acc)
fuseFilterAccEFL f g (noAcc :*: acc) e1 =
  case f e1 of
    False -> (noAcc :*: acc) :*: NothingS
    True  ->
      case g acc e1 of
        acc' :*: res -> (noAcc :*: acc') :*: res

fuseNoAccFilterEFL :: NoAccEFL -> FilterEFL -> NoAccEFL
fuseNoAccFilterEFL f g e1 =
  case f e1 of
    NothingS -> NothingS
    JustS e2 ->
      case g e2 of
        False -> NothingS
        True  -> JustS e2

fuseFilterNoAccEFL :: FilterEFL -> NoAccEFL -> NoAccEFL
fuseFilterNoAccEFL f g e1 =
  case f e1 of
    False -> NothingS
    True  -> g e1

fuseFilterFilterEFL :: FilterEFL -> FilterEFL -> FilterEFL
fuseFilterFilterEFL f g e1 = f e1 && g e1


fuseMapFilterEFL :: MapEFL -> FilterEFL -> NoAccEFL
fuseMapFilterEFL f g e1 =
  case f e1 of
    e2 -> case g e2 of
            False -> NothingS
            True  -> JustS e2

fuseFilterMapEFL :: FilterEFL -> MapEFL -> NoAccEFL
fuseFilterMapEFL f g e1 =
  case f e1 of
    False -> NothingS
    True  -> JustS (g e1)
-}