module compress.BriefLz;

private import compress.model.IDecompressor;
private import compress.DataFileUtils;

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
                    state = cast(ushort)(inData.getShort);

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

                        writeBack(outDataIn, outDataOut, off, len);
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
