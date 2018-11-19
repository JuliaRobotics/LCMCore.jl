mutable struct MyMessage
    field1::Int32
    field2::Float64
end

function encode(msg::MyMessage)
    buf = IOBuffer()
    write(buf, hton(msg.field1))
    write(buf, hton(msg.field2))
    buf.data
end

function decode(data, msg::Type{MyMessage})
    buf = IOBuffer(data)
    MyMessage(ntoh(read(buf, Int32)), ntoh(read(buf, Float64)))
end
