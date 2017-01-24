# LCMCore: Low-level Julia bindings for LCM

[![Build Status](https://travis-ci.org/rdeits/LCMCore.jl.svg?branch=master)](https://travis-ci.org/rdeits/LCMCore.jl)
[![codecov.io](https://codecov.io/github/rdeits/LCMCore.jl/coverage.svg?branch=master)](https://codecov.io/github/rdeits/LCMCore.jl?branch=master)

LCMCore.jl provides a low-level Julia interface to the [Lightweight Communications and Marshalling (LCM) library](https://lcm-proj.github.io/). It uses LCM by calling directly into the C library, so it should have very low overhead.

**Note:** This is not a full-fledged LCM implementation. Most notably, there is no tool to automatically generate Julia encoder/decoder functions for LCM message types. Fortunately, it is relatively easy to implement this functionality by hand for simple LCM types. For more complicated messages, you may want to use [PyLCM](https://github.com/rdeits/PyLCM.jl), which uses this library for the LCM interface and uses the LCM Python bindings to encode and decode messages easily. 
