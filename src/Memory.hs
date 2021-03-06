module Memory (Memory, create, issueRead, issueWrite, elapse, isBusy) where

import Definitions

-- Constants describing number of cycles for read/write operation
readCycles :: Int
readCycles = 100

writeCycles :: Int
writeCycles = 100

data Memory = Memory NumCycles

create :: Memory
create = Memory 0

issueRead :: Memory -> Memory
issueRead memory = newMemory where
    newMemory = Memory readCycles

issueWrite :: Memory -> Memory
issueWrite memory = newMemory where
    newMemory = Memory writeCycles

elapse :: Memory -> Memory
elapse (Memory oldBusyCycles) = newMemory where
    newMemory = Memory newBusyCycles where
        newBusyCycles = max (oldBusyCycles - 1) 0

isBusy :: Memory -> IsBusy
isBusy (Memory busyCycles) = busyCycles /= 0
