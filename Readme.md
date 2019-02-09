# LCMCore: Low-level Julia bindings for LCM

[![Build Status](https://travis-ci.org/JuliaRobotics/LCMCore.jl.svg?branch=master)](https://travis-ci.org/JuliaRobotics/LCMCore.jl)
[![codecov.io](https://codecov.io/github/JuliaRobotics/LCMCore.jl/coverage.svg?branch=master)](https://codecov.io/github/JuliaRobotics/LCMCore.jl?branch=master)

LCMCore.jl provides a low-level Julia interface to the [Lightweight Communications and Marshalling (LCM) library](https://lcm-proj.github.io/). It uses LCM by calling directly into the C library, so it should have very low overhead.

**Note:** This is not a full-fledged LCM implementation. Most notably, there is no `lcm-gen` tool to automatically generate Julia encoder/decoder functions for LCM message types. Fortunately, we provide a helpful Julia macro to [automate most of the process](#pure-julia-lcmtype-and-lcmtypesetup).

# Installation

The following package is required (Ubuntu 18.04):
```bash
sudo apt-get install libglib2.0-dev
```

From Julia, you can do:

```julia
Pkg.add("LCMCore")
```

Installing LCMCore.jl will automatically download and build a new copy of the LCM library for you.

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

LCMCore.jl supports Julia's async model internally, so setting up an asynchronous handler task is as easy as:

```julia
@async while true
    handle(lcm)
end
```

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

## Message Types

Calling `subscribe()` with three arguments, like this: `subscribe(lcm, channel, callback)` will result in your callback being called with the raw byte array received by LCM. You are then responsible for decoding that byte array as a particular message type.

Since that's probably inconvenient, there's another way to call subscribe:

```julia
mutable struct MyMessageType
    <your code here>
end

function callback(channel::String, msg::MyMessageType)
    @show channel
    @show msg
end

subscribe(lcm, "MY_CHANNEL", callback, MyMessageType)
```

When `subscribe()` is called with the message type as the final argument, your callback will receive the decoded message directly, instead of the raw bytes.

To make this work, you have to define two methods, `encode()` and `decode()`

```julia
import LCMCore: encode, decode

encode(msg::MyMessageType) = <serialize your message as a Vector{UInt8}>

decode(data::Vector{UInt8}, ::Type{MyMessageType}) = <return an instance of MyMessageType from the given data>
```

## Complex Message Types

Manually defining `encode()` and `decode()` functions is annoying, so we provide a convenient way to automate the process:

LCMCore.jl provides the `LCMType` abstract type and the `@lcmtypesetup` macro to make it easy to describe LCM message types in pure Julia. To use this approach, simply create a `mutable struct` which is a subtype of `LCMType`, and make sure that struct's field names and types match the LCM type definition. For a real-world example, check out CaesarLCMTypes.jl:

* Type definition: [example_t.jl](https://github.com/JuliaRobotics/CaesarLCMTypes.jl/blob/bb26d44b1b04ba777049ec7f62f070e8ff2df5c5/src/example_t.jl)
* Sender: [example_sender.jl](https://github.com/JuliaRobotics/CaesarLCMTypes.jl/blob/bb26d44b1b04ba777049ec7f62f070e8ff2df5c5/examples/example_sender.jl)
* Listener: [example_listener.jl](https://github.com/JuliaRobotics/CaesarLCMTypes.jl/blob/bb26d44b1b04ba777049ec7f62f070e8ff2df5c5/examples/example_listener.jl)

or for more detailed information, keep reading. For example, given this LCM type:

```c
struct example_t {
  int64_t timestamp;
  double position[3];
  string name;
}
```

we would manually create the following Julia struct definition:

```julia
using LCMCore, StaticArrays

mutable struct example_t <: LCMType
  timestamp::Int64
  position::SVector{3, Float64}
  name::String
end

@lcmtypesetup(example_t)
```

The call to `@lcmtypesetup(example_t)` analyzes the field names and types of our Julia struct to generate efficient `encode()` and `decode()` methods. Note the use of SVectors from StaticArrays.jl to represent the fixed-length `position` array in the LCM type.

LCM types frequently contain variable-length vectors of primitives or other LCM types. For example, if we have the following LCM type definition:

```c
struct example_vector_t {
  int32_t num_floats;
  float data[num_floats];

  int32_t num_examples;
  example_t examples[num_examples];
}
```

then we simply need to pass two additional arguments to `@lcmtypesetup`:

```julia
mutable struct example_vector_t <: LCMType
  num_floats::Int32
  data::Vector{Float32}

  num_examples::Int32
  examples::Vector{example_t}  # where example_t is the Julia struct we defined earlier
end

@lcmtypesetup(example_vector_t,
  data => (num_floats,),
  examples => (num_examples,)
)
```

The format of each additional argument to `@lcmtypesetup` is `field_name => tuple_of_size_fields`.

Multi-dimensional arrays are also supported, including arrays with some fixed dimensions and some variable dimensions:

```c
struct matrix_example_t {
  int32_t rows;
  int32_t cols;
  float data[rows][cols];

  int32_t num_points;
  float coordinates[3][num_points];
}
```

in Julia, we would do:

```julia
mutable struct matrix_example_t <: LCMType
  rows::Int32
  cols::Int32
  data::Matrix{Float32}

  num_points::Int32
  coordinates::Matrix{Float32}
end

@lcmtypesetup(matrix_example_t,
  data => (rows, cols),
  coordinates => (3, num_points)
)
```

## Reading LCM log files directly

LCM log files can also be read directly, without the UDP multicasting events.
Events are read from file one at a time and use a similar API as the UDP traffic interface.
```julia
function callback(channel, msgdata)
  msg = decode(MsgType, msgdata) # slower, fresh memory allocation -- consider typedcallback(...) with decode! instead
  @show msg
  # ...
  nothing
end

function typed_callback(channel, msg::MsgType)
  @show msg
  # ...
  nothing
end

lcm = LCMLog("log.lcm")
#subscribe(lcm, "CHANNEL", callback )
subscribe(lcm, "CHANNEL", typed_callback, MsgType )

while true
  handle(lcm)
end
```

See the `test` folder for a more detailed example.
