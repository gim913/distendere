module compress.Lzss;

private import compress.model.IDecompressor;

private import tango.io.model.IConduit;
private import tango.core.Exception;
private import tango.io.stream.Data;
private import tango.util.log.Log;

private import tango.io.Stdout;

private Logger log;

static this()
{
    log = Log.lookup ("compress.Lzss");
}

class Lzss(size_t Offset_Bits = 12, size_t Length_Bits = 4) : IDecompressor
{
    private:
        static const size_t Window_Size = (1 << Offset_Bits);
        ubyte slidingWindow[];

    public:
        this(ubyte fillWindow = ' ') {
            slidingWindow.length = Window_Size;
            slidingWindow[] = fillWindow;
            log.trace(" off: {} len: {}", Offset_Bits, Length_Bits);
        }

        void decompressStream(InputStream inStream, IConduit outStream, int unpSize = -1) {
            if (log.enabled(log.Trace)) { 
                log.trace("in decompress()");
            }

            auto inData = new DataInput(inStream);
            auto outDataIn = new DataInput(outStream);
            auto outDataOut = new DataOutput(outStream);
            size_t bitCount; // 0
            uint state; // for keeping bits, 0

            uint getBit() {
                if (! bitCount-- ) {
                    state = cast(ubyte)(inData.getByte);
                    if (log.enabled(log.Trace)) log.trace("state: {:x2}", state);
                    bitCount = 7;
                }
                log.trace("got bit, current bitcount: {}", bitCount);

                uint singleBit = state & 0x80;
                state <<= 1;
                return !!singleBit;
            }

            uint getByte() {
                size_t num = 8;
                int ret;
                log.trace("getting bits, current bitcount: {}", bitCount);
                int i;
                while(1) {
                    if (num <= bitCount) {
                        ret <<= num;
                        ret |= ( (state & 0xff) >> (8 - num));
                        state <<= num;
                        bitCount -= num;
                        break;

                    } else {
                        log.trace("{} vs {}", num, bitCount);
                        ret <<= bitCount;
                        ret |= ( (state & 0xff) >> (8 - bitCount));
                        state <<= bitCount;
                        num -= bitCount;

                        state = cast(ubyte)(inData.getByte);
                        bitCount = 8;
                    }
                }

                return ret;
            }

            // 11 22 3x ..
            uint getBits(size_t num) {
                int ret;
                log.trace("getting bits, current bitcount: {}", bitCount);
                uint temp;
                int i;
                while (num >= 8) {
                    temp |= cast(ubyte)(getByte) << i;
                    i += 8;
                    num -= 8;
                }
                log.trace("getting bits, current temp: {}", temp);

                while(1) {
                    if (num <= bitCount) {
                        ret <<= num;
                        ret |= ( (state & 0xff) >> (8 - num));
                        state <<= num;
                        bitCount -= num;
                        break;

                    } else {
                        log.trace("{} vs {}", num, bitCount);
                        ret <<= bitCount;
                        ret |= ( (state & 0xff) >> (8 - bitCount));
                        state <<= bitCount;
                        num -= bitCount;

                        state = cast(ubyte)(inData.getByte);
                        bitCount = 8;
                    }
                }

                temp |= (ret << i);
                return temp;
            }

            long off;
            size_t idx = 0;
            ubyte[] uncoded;
            uncoded.length = Window_Size;
            try {
                while (1) {
                    if (getBit()) {
                        ubyte b = getByte;
                        outDataOut.putByte(b);
                        slidingWindow[idx++] = b;
                        idx %= Window_Size;
                        if (log.enabled(log.Trace)) log.trace("byte: {:x2}", b);

                    } else {
                        off = getBits(Offset_Bits);
                        int len = getBits(Length_Bits);

                        len += 2 + 1;

                        if (log.enabled(log.Trace)) log.trace("off {} len {}", off, len);

                        assert (Window_Size > len);

                        /+
                        size_t tempLen = len;
                        do {
                            len = tempLen > Window_Size ? Window_Size : tempLen;
                        +/

                        off %= Window_Size;
                        size_t cur = off + len > Window_Size ? (Window_Size - off) : len;
                        uncoded[0 .. cur] = slidingWindow[off .. (off + cur)];
                        if (cur != len) {
                            uncoded[cur .. len] = slidingWindow[0 .. (len - cur)];
                        }

                        outDataOut.write(uncoded[0 .. len]);

                        // update sliding window with written bytes
                        cur = idx + len > Window_Size ? (Window_Size - idx) : len;
                        slidingWindow[idx .. (idx + cur)] = uncoded[0 .. cur];
                        if (cur != len) {
                            slidingWindow[0 .. (len - cur)] = uncoded[cur .. len];
                        }

                        idx += len;
                        idx %= Window_Size;

                        /+
                            tempLen -= len;
                        } while (tempLen > 0);
                        +/
                    }
                }

            } catch (IOException o) {
                // silently eat that exceptions
                if ("DataInput :: unexpected eof while reading" != o.msg) {
                    throw o;
                }
            }

            outDataOut.flush;
        }
}
