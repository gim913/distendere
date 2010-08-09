module compress.BriefLz;

private import compress.model.IDecompressor;

private import tango.io.model.IConduit;
private import tango.core.Exception;
private import tango.io.stream.Data;
private import tango.util.log.Log;
private import tango.io.Stdout;

private Logger log;

static this()
{
    log = Log.lookup ("compress.BriefLz");
}

class BriefLz : IDecompressor
{
    private:
    public:
        this() {
        }
        void decompressStream(InputStream inStream, IConduit outStream, int unpackSize = -1) {
            if (log.enabled(log.Trace)) { 
                log.trace("in decompress()");
            }

            auto inData = new DataInput(inStream);
            auto outDataIn = new DataInput(outStream);
            auto outDataOut = new DataOutput(outStream);
            size_t bitCount; // 0
            uint state; // 0

            uint getBit() {
                if (! bitCount-- ) {
                    state = cast(ubyte)(inData.getByte);
                    state |= cast(ubyte)(inData.getByte) << 8;
                    if (log.enabled(log.Trace)) log.trace("state: {:x4}", state);
                    bitCount = 15;
                }
                log.trace("got bit, current bitcount: {}", bitCount);

                uint singleBit = state & 0x8000;
                state <<= 1;
                return !!singleBit;
            }
            uint getGamma() {
                uint gamma = 1;
                do {
                    gamma = (gamma << 1) | getBit();
                } while (getBit());
                return gamma;
            }

            void writeBack(long off, int len) {
                ubyte tempBuf[];
                tempBuf.length = len;
                debug tempBuf[] = 0xCC;

                outDataOut.flush;
                log.trace("off: {} len: {} 0x{:x} vs {} ", off, len, len, outDataIn.seek(0, IOStream.Anchor.End) );
                outDataIn.seek(-off, IOStream.Anchor.End);
                if (off < len) {
                    size_t dataRead = outDataIn.read(tempBuf[0 .. off]);

                    // fast-fill-in the buffer
                    size_t cur = off;
                    size_t tempLen = off;

                    do {
                        if (cur + tempLen > len) tempLen = len - cur;
                        tempBuf[cur .. cur + tempLen] = tempBuf[0 .. tempLen];
                        log.trace("filling: {:x2} - {:x2} with 0 - {:x2}", cur, cur + tempLen, tempLen);
                        if (cur + tempLen == len) break;
                        cur *= 2;
                        tempLen *= 2;
                    } while (1);

                    log.trace("data read {}", dataRead);

                    outDataOut.write(tempBuf);
                    outDataOut.flush;

                } else {
                    size_t dataRead = outDataIn.read(tempBuf);
                    log.trace("data read {}", dataRead);

                    outDataOut.seek(0, IOStream.Anchor.End);
                    outDataOut.write(tempBuf);
                }
            }

            long off;
            try {
                outDataOut.putByte( inData.getByte );
                int alreadyUnpacked = 1;
                while (1) {
                    if (getBit()) {
                        int len = getGamma() + 2;
                        off = getGamma() - 2;

                        off = (off << 8) + cast(ubyte)(inData.getByte) + 1;
                        if (log.enabled(log.Trace)) log.trace("len: {} off: {}, current {}", len, off, alreadyUnpacked);

                        assert(off <= alreadyUnpacked);
                        assert (off != 0);

                        writeBack(off, len);
                        alreadyUnpacked += len;

                    } else {
                        ubyte b = cast(ubyte)(inData.getByte);
                        outDataOut.putByte(b);
                        if (log.enabled(log.Trace)) log.trace("byte: {:x2}", b);
                        alreadyUnpacked++;
                    }

                    if (unpackSize != -1) {
                        if (alreadyUnpacked >= unpackSize) {
                            break;
                        }
                    }
                }

            } catch(IOException o) {
                if (-1 != unpackSize || "DataInput :: unexpected eof while reading" != o.msg) {
                    throw o;
                }
            }

            outDataOut.flush;
        }
}
