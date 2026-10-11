module Frames

open System.Threading.Tasks

type IFrameSource =
    abstract ReadAsync: unit -> Task<int>

let sumFrames (source: IFrameSource) (count: int) : Task<int> =
    task {
        let mutable total = 0
        for _ in 1..count do
            let! frame = source.ReadAsync()
            total <- total + frame
        return total
    }

let readWithTimeout (source: IFrameSource) (timeoutMs: int) : Task<int option> =
    task {
        let read = source.ReadAsync()
        let! winner = Task.WhenAny(read, Task.Delay timeoutMs)
        if obj.ReferenceEquals(winner, read) then
            return Some read.Result
        else
            return None
    }

let readLabelled (source: IFrameSource) (label: string) : Task<string> =
    task {
        let read = source.ReadAsync()
        let! frame = read
        if frame < 0 then
            return $"{label}: invalid frame {read.Result}"
        else
            return $"{label}: {frame}"
    }
