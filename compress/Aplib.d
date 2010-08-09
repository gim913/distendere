module compress.Aplib;

private import compress.model.IDecompressor;

private import tango.io.model.IConduit;
private import tango.io.stream.Data;
private import tango.util.log.Log;

private import tango.io.Stdout;

private Logger log;

static this()
{
    log = Log.lookup ("compress.Aplib");
}

class Aplib(int State_Bit_Count) : IDecompressor
{
    private:
    public:
        this() {
        }

        void decompressStream(InputStream inStream, IConduit outStream, int unpSize = -1) {
            if (log.enabled(log.Trace)) { 
                log.trace("in decompress()");
            }

            auto inData = new DataInput(inStream);
            auto outDataIn = new DataInput(outStream);
            auto outDataOut = new DataOutput(outStream);
            size_t bitCount; // 0
            uint state; // 0

            static if(State_Bit_Count == 8) {
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
                uint getGamma() {
                    uint gamma = 1;
                    do {
                        gamma = (gamma << 1) | getBit();
                    } while (getBit());
                    return gamma;
                }
                uint getBits(size_t num) {
                    int ret;
                    log.trace("getting bits, current bitcount: {}", bitCount);
                    while(1) {
                        if (num <= bitCount) {
                            ret <<= num;
                            ret |= ( (state & 0xff) >> (State_Bit_Count - num));
                            state <<= num;
                            bitCount -= num;
                            break;

                        } else {
                            log.trace("{} vs {}", num, bitCount);
                            ret <<= bitCount;
                            ret |= ( (state & 0xff) >> (State_Bit_Count - bitCount));
                            state <<= bitCount;
                            num -= bitCount;

                            state = cast(ubyte)(inData.getByte);
                            bitCount = 8;
                        }
                    }
                    return ret;
                }
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

            outDataOut.putByte( inData.getByte );

            bool done;
            bool LWM;
            long prevOff;
            debug bool prevInitialized;

            // 111 - (get 4bit offs), copy byte
            // 110 - (get 7bit off, 1bit len), off==0->done
            // 10 - getGamma
            // 0 -  copy byte
            long off;
            while (!done) {
                if (getBit()) {
                    if (getBit()) {
                        if (getBit()) {
                            if (log.enabled(log.Trace)) log.trace("BRANCH 111");

                            off = getBits(4);
                            if (log.enabled(log.Trace)) log.trace("off: {:x2}", off);

                            if (off) {
                                outDataOut.flush;
                                size_t t = outDataIn.seek(-off, IOStream.Anchor.End);
                                auto b = outDataIn.getByte;
                                outDataOut.seek(0, IOStream.Anchor.End);
                                outDataOut.putByte(b);

                            } else {
                                outDataOut.putByte( 0 );
                            }

                            LWM = false;

                        } else {
                            if (log.enabled(log.Trace)) log.trace("BRANCH 110");
                            off = cast(ubyte)( inData.getByte );
                            int len = 2 + (off & 1);
                            off >>= 1;

                            if (off) {
                                writeBack(off, len);

                                prevOff = off;
                                LWM = true;
                            } else {
                                done = true;
                            }
                        }

                    } else {
                        if (log.enabled(log.Trace)) log.trace("BRANCH 10x");
                        off = getGamma;
                        if (log.enabled(log.Trace)) log.trace("gamma off: {}", off);

                        if ( !LWM && 2 == off ) {
                            debug assert (prevInitialized);
                            
                            off = prevOff;
                            int len = getGamma;
                            writeBack(off, len);

                        } else {
                            if (! LWM) {
                                off -= 3;

                            } else {
                                off -= 2;
                            }

                            outDataOut.flush;
                            if (log.enabled(log.Trace)) log.trace("gamma off: {}", off);
                            off <<= 8;
                            if (log.enabled(log.Trace)) log.trace("gamma off: {}", off);
                            off |= cast(ubyte)( inData.getByte );
                            if (log.enabled(log.Trace)) log.trace("gamma off: {}", off);

                            int len = getGamma;
                            if (log.enabled(log.Trace)) log.trace("gamma: {}, off {}", len, off);
                            if (off >= 32000) ++len;
                            if (off >= 1280) ++len;
                            if (off < 128) len += 2;

                            writeBack(off, len);

                            prevOff = off;
                            debug prevInitialized = true;
                        }

                        LWM = true;
                    }

                } else {
                    if (log.enabled(log.Trace)) log.trace("BRANCH 0xx");
                    outDataOut.putByte( inData.getByte );
                    LWM = false;
                }
            }
            outDataOut.flush;
        }
}
