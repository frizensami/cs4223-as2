module Simulator
    ( runSimulation
    ) where

import Trace
import Processor (createProcessor)
import Definitions
import Control.Monad (liftM)



-- Defining constants
num_processors = 4

-- |Given appropriate cmd line arguments, runs the entire cache simulation and results the stats results
runSimulation :: ProtocolInput -> Filename -> CacheSize -> Associativity -> BlockSize -> IO String
runSimulation protocolInput fileName cacheSize associativity blockSize = 
    do
        let 

            -- Parse the protocol
            -- Possible error with read here if bad input given
            protocol = read protocolInput :: Protocol 
            
            -- Read the input files
            -- Create exactly 4 trace files names
            fileNames = map (\n -> fileName ++ "_" ++ show n ++ ".data") [0..(num_processors-1)] 

            -- Create a set of strings, each will lazily read from the file as needed (IO [String]])
            fileStrings = mapM (readFile) fileNames 

            -- Read the list of strings from the file read process into a list of list of lines
            -- Each element of the list is a list of the lines from a single file
            -- liftM applies this composed & curried function into the list monad
            fileLines = liftM (map lines) fileStrings

            -- Map each of these lines to a trace
            -- This is now of type IO [[Trace]] where each outer list element is one processor
            -- and the inner lists are the traces for that processor
            tracesIO = liftM (map $ map toTraceWithError) fileLines

            -- Initialize as many processors as we need in their initial states
            newProcessor = createProcessor protocolInput cacheSize associativity blockSize
            processorsList = replicate num_processors newProcessor

            -- Execute 
            -- Until ALL PROCESSORS ARE COMPLETE and ALL TRACE LISTS ARE EMPTY - we keep executing

        -- Get the entire list of pure traces from the IO [[Trace]] structure
        tracesList <- tracesIO
        -- Now run one round of the simulation loop and see if a core needs another instruction
        return "Simulation Completed"

-- General idea: for each processor, execute the new trace if there is one, or continue with current action. Then, propagate the bus events to ALL OTHER PROCESSORS: aka all other processors MUST RESPOND to the bus event before this processors' CYCLE is over. Then, repeat for the rest. Check when more awake whether this makes sense. Therefore, processor 1 always has priority, followed by 2...etc. Deterministic
-- Morning note: this makes sense. It's almost like each processor is running sequentially with a particular priority on each cycle, which could happen in a particularly biased computer.

-- |Runs a single cycle for a single processor. Attempts to feed it a list of traces. The processor may consume some part of the list of traces, then return a new Processor instance (the new processor state essentially), the remaining traces to be consumed, and a list of bus events generated by this processor
-- runOneProcessorCycle :: Processor -> [Trace] -> (Processor, [Trace], [BusEvent])
-- runOneProcessorCycle processor tracexs = 