# LCMCore: Low-level Julia bindings for LCM

[![Build Status](https://travis-ci.org/rdeits/LCMCore.jl.svg?branch=master)](https://travis-ci.org/rdeits/LCMCore.jl)
[![codecov.io](https://codecov.io/github/rdeits/LCMCore.jl/coverage.svg?branch=master)](https://codecov.io/github/rdeits/LCMCore.jl?branch=master)

LCMCore.jl provides a low-level Julia interface to the [Lightweight Communications and Marshalling (LCM) library](https://lcm-proj.github.io/). It uses LCM by calling directly into the C library, so it should have very low overhead.

**Note:** This is not a full-fledged LCM implementation. Most notably, there is no `lcm-gen` tool to automatically generate Julia encoder/decoder functions for LCM message types. Fortunately, it is relatively easy to implement this functionality by hand for simple LCM types. For more complicated messages, you may want to use [PyLCM](https://github.com/rdeits/PyLCM.jl), which uses this library for the LCM interface and uses the LCM Python bindings to encode and decode messages easily.

# Installation

From Julia, you can do:

```julia
Pkg.add("LCMCore")
```

If you have LCM installed systemwide, LCMCore.jl will try to use that installation. Otherwise, it will download and build a new copy of the LCM library for you.

# Usage

This interface has been designed to be similar to the LCM Python interface.

Create an LCM interface object:

```julia
lcm = LCM()
```

Subscribe to a particular channel, using a callback:

```julia
function callback(channel::String, message_data::Vector{UInt8})
    @show channel
    @show message_data
end

subscribe(lcm, "MY_CHANNEL", callback)
```

Publish a raw byte array to a channel:

```julia
publish(lcm, "MY_CHANNEL", UInt8[1,2,3,4])
```

Receive a single message and dispatch its callback:

```julia
handle(lcm)
```

## Asynchronous Handling

LCMCore.jl supports Julia's async model internally, so setting up an asynchronous handler thread is as easy as:

```julia
@async while true
    handle(lcm)
end
```

## Message Types

Calling `subscribe()` with three arguments, like this: `subscribe(lcm, channel, callback)` will result in your callback being called with the raw byte array received by LCM. You are then responsible for decoding that byte array as a particular message type.

Since that's probably inconvenient, there's another way to call subscribe:

```julia
type MyMessageType
    <your code here>
end

function typed_callback(channel::String, msg::MyMessageType)
    @show channel
    @show msg
end

subscribe(lcm, "MY_CHANNEL", typed_callback, MyMessageType)
```

When `subscribe()` is called with the message type as the final argument, your callback will receive the decoded message directly, instead of the raw bytes.

To make this work, you have to define two methods, `encode()` and `decode()`

```julia
import LCMCore: encode, decode

encode(msg::MyMessageType) = <serialize your message as a Vector{UInt8}>

decode(data::Vector{UInt8}, ::Type{MyMessageType}) = <return an instance of MyMessageType from the given data>
```

## Complex Message Types

Manually defining `encode()` and `decode()` functions is annoying. The easiest way to avoid this is to use [PyLCM.jl](https://github.com/rdeits/PyLCM.jl). PyLCM.jl uses LCMCore.jl under the hood, and also allows you to also encode and decode any Python LCM type automatically.

## Closing the LCM Object

Spawning lots of LCM objects can result in your system running out of file descriptors. This rarely occurs in practice, but if it does happen, you can close an LCM object with:

```julia
close(lcm)
```

It's safe to call `close()` multiple times on the same LCM object.

To deterministically close an LCM automatically, you can use the do-block syntax:

```julia
LCM() do lcm
    publish(lcm, channel, message)
end
```

which will automatically close the LCM object at the end of the block.

## Reading LCM log files directly

LCM log files can also be read directly, without the UDP multicasting events.
Events are read from file one at a time and use a similar API as the UDP traffic interface.
```julia
function callback(channel, msgdata)
  msg = covert(MsgType, msgdata) # decode
  # ...
  nothing
end

lcm = LCMlog("log.lcm")
subscribe(lc, "CHANNEL", callback )
#subscribe(lc, "CHANNEL", typedcallback, MsgType )

while handle(lcm); end
```

See the `test` folder for a more detailed example.
