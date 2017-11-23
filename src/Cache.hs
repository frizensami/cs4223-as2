module Cache (Cache, getCacheParams, create, issueRead, commitRead, issueWrite, commitWrite, busGetBlockState, busSetBlockState, busAllocate, busEvict, elapse, isCacheHit) where

import CacheParams (CacheParams)
import qualified CacheParams
import CacheSet (CacheSet)
import qualified CacheSet
import CacheBlock (BlockState (..))
import Data.Array as Array
import Definitions
import qualified MemoryAddress

readCycles :: Int
readCycles = 1

writeCycles :: Int
writeCycles = 1

type IsCacheHit = Bool

data Cache = Cache CacheParams (Array Int CacheSet) NumCycles (Maybe IsCacheHit)

getCacheParams :: Cache -> CacheParams
getCacheParams (Cache cacheParams _ _ _) = cacheParams

-- |Creates an empty cache with the specified cache size, associativity, and block size.
--  Returns the empty cache on successful execution.
create :: CacheSize -> Associativity -> BlockSize -> Cache
create cacheSize associativity blockSize = Cache cacheParams cacheSets busyCycles maybeIsCacheHit where
    cacheParams = CacheParams.create cacheSize associativity blockSize

    cacheSets = Array.array (0, lastIndex) [(i, cacheSet) | i <- [0..lastIndex]] where
        lastIndex = (CacheParams.getNumCacheSets cacheParams) - 1
        cacheSet = CacheSet.create associativity blockSize

    busyCycles = 0

    maybeIsCacheHit = Nothing

-- |Issues a cache read of a memory address on the specified cache.
--  Returns the renewed cache.
issueRead :: MemoryAddress -> Cache -> Cache
issueRead memoryAddress (Cache oldCacheParams oldCacheSets _ _) = newCache where
    (blockTag, setIndex, _) = MemoryAddress.parse oldCacheParams memoryAddress

    newCache = Cache oldCacheParams oldCacheSets readCycles maybeIsCacheHit where
        maybeIsCacheHit = Just $ CacheSet.hasTag blockTag $ oldCacheSets!setIndex

-- |Issues a cache read commit of a memory address on the specified cache.
--  Returns the renewed cache.
commitRead :: MemoryAddress -> Cache -> Cache
commitRead memoryAddress (Cache oldCacheParams oldCacheSets 0 (Just True)) = newCache where
    (blockTag, setIndex, offset) = MemoryAddress.parse oldCacheParams memoryAddress

    newCache = Cache oldCacheParams newCacheSets 0 $ Just True where
        newCacheSets = oldCacheSets//[(i, newCacheSet) | i <- [setIndex]] where
            newCacheSet = CacheSet.allocate evictedBlockState blockTag offset memoryAddress evictedCacheSet where
                (evictedBlockState, evictedCacheSet) = CacheSet.evict blockTag oldCacheSet where
                    oldCacheSet = oldCacheSets!setIndex
commitRead memoryAddress (Cache _ _ _ _) = error "Commit read when cache is still busy or cache miss"

-- |Issues a cache write of a memory address to the specified cache.
--  Returns the renewed cache.
issueWrite :: MemoryAddress -> Cache -> Cache
issueWrite memoryAddress (Cache oldCacheParams oldCacheSets _ _) = newCache where
    (blockTag, setIndex, _) = MemoryAddress.parse oldCacheParams memoryAddress

    newCache = Cache oldCacheParams oldCacheSets writeCycles maybeIsCacheHit where
        maybeIsCacheHit = Just $ CacheSet.hasTag blockTag $ oldCacheSets!setIndex

commitWrite :: MemoryAddress -> Cache -> Cache
commitWrite memoryAddress (Cache oldCacheParams oldCacheSets 0 (Just True)) = newCache where
    (blockTag, setIndex, offset) = MemoryAddress.parse oldCacheParams memoryAddress

    newCache = Cache oldCacheParams newCacheSets 0 $ Just True where
        newCacheSets = oldCacheSets//[(i, newCacheSet) | i <- [setIndex]] where
            newCacheSet = CacheSet.allocate modifiedState blockTag offset memoryAddress evictedCacheSet where
                modifiedState = case evictedBlockState of
                    M   -> M
                    E   -> M
                    S   -> M
                    SC  -> M
                    SM  -> M
                    I   -> error "Cache hit on I state"
                (evictedBlockState, evictedCacheSet) = CacheSet.evict blockTag oldCacheSet where
                    oldCacheSet = oldCacheSets!setIndex
commitWrite memoryAddress (Cache _ _ _ _) = error "Commit write when cache is still busy or cache miss"

busGetBlockState :: MemoryAddress -> Cache -> (Maybe BlockState)
busGetBlockState memoryAddress (Cache oldCacheParams oldCacheSets _ _) = maybeBlockState where
    maybeBlockState = CacheSet.getBlockState blockTag cacheSet where
        (blockTag, setIndex, _) = MemoryAddress.parse oldCacheParams memoryAddress

        cacheSet = oldCacheSets!setIndex

-- |Sets the block state of the block the memory address resides in to the specified block state.
--  Returns the renewed cache.
busSetBlockState :: BlockState -> MemoryAddress -> Cache -> Cache
busSetBlockState blockState memoryAddress (Cache oldCacheParams oldCacheSets oldBusyCycles oldMaybeIsCacheHit) = newCache where
    newCache = Cache oldCacheParams newCacheSets oldBusyCycles oldMaybeIsCacheHit where
        newCacheSets = oldCacheSets//[(i, newCacheSet) | i <- [setIndex]] where
            (blockTag, setIndex, _) = MemoryAddress.parse oldCacheParams memoryAddress
            newCacheSet = CacheSet.setBlockState blockState blockTag oldCacheSet where
                oldCacheSet = oldCacheSets!setIndex

-- |Allocates a memory address on the specified cache.
--  Returns the evicted block state (if any) and the renewed cache.
busAllocate :: BlockState -> MemoryAddress -> Cache -> (Maybe BlockState, Cache)
busAllocate blockState memoryAddress (Cache oldCacheParams oldCacheSets oldBusyCycles oldMaybeIsCacheHit) = (maybeEvictedBlockState, newCache) where
    (blockTag, setIndex, offset) = MemoryAddress.parse oldCacheParams memoryAddress

    (maybeEvictedBlockState, newCacheSet)
        | CacheSet.canAllocate oldCacheSet  = (Nothing, CacheSet.allocate blockState blockTag offset memoryAddress oldCacheSet)
        | otherwise                         = (Just evictedBlockState, CacheSet.allocate blockState blockTag offset memoryAddress evictedCacheSet)
        where
            oldCacheSet = oldCacheSets!setIndex
            (evictedBlockState, evictedCacheSet) = CacheSet.evictLRU oldCacheSet

    newCache = Cache oldCacheParams newCacheSets oldBusyCycles oldMaybeIsCacheHit where
        newCacheSets = oldCacheSets//[(i, newCacheSet) | i <- [setIndex]]

-- |Evicts a memory address from the specified cache.
--  Returns the evicted block state and the renewed cache.
busEvict :: MemoryAddress -> Cache -> (BlockState, Cache)
busEvict memoryAddress (Cache oldCacheParams oldCacheSets oldBusyCycles oldMaybeIsCacheHit) = (evictedBlockState, newCache) where
    (blockTag, setIndex, _) = MemoryAddress.parse oldCacheParams memoryAddress

    (evictedBlockState, newCacheSet) = CacheSet.evict blockTag oldCacheSet where
        oldCacheSet = oldCacheSets!setIndex

    newCache = Cache oldCacheParams newCacheSets oldBusyCycles oldMaybeIsCacheHit where
        newCacheSets = oldCacheSets//[(i, newCacheSet) | i <- [setIndex]]

elapse :: Cache -> Cache
elapse (Cache oldCacheParams oldCacheSets oldBusyCycles oldMaybeIsCacheHit) = newCache where
    newCache = Cache oldCacheParams oldCacheSets newBusyCycles oldMaybeIsCacheHit where
        newBusyCycles = max (oldBusyCycles - 1) 0

isCacheHit :: Cache -> Maybe IsCacheHit
isCacheHit (Cache _ _ busyCycles maybeIsCacheHit)
    | busyCycles == 0   = maybeIsCacheHit
    | otherwise         = Nothing
