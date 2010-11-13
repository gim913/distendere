module compress.QuickLz;

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
    log = Log.lookup ("compress.QuickLz");
}

class QuickLz(int Compression_Level) : IDecompressor
{
    static assert(Compression_Level == 1 || Compression_Level == 2 || Compression_Level == 3 || "Compression_Level must be 1, 2 or 3");
    private:
    public:
    this() {
    }
    void decompressStream(InputStream inStream, IConduit outStream, int unpackSize = -1) {
        //if (log.enabled(log.Trace)) { log.trace("in decompress(,,{})", unpackSize); }
        assert (unpackSize != -1);

        auto inData = new DataInput(inStream);
        auto outDataIn = new DataInput(outStream);
        auto outDataOut = new DataOutput(outStream);
        size_t bitCount; // 0
        uint state; // 0
        static if (Compression_Level == 1 || Compression_Level == 2) {
            hashCounter[] = 0; // reset hash state
        }

        void getCodeword() {
            if (state == 1 || ! bitCount-- ) {
                state = cast(uint)(inData.getInt);

                if (log.enabled(log.Trace)) log.trace("state: {:x8}", state);
                bitCount = 31;
            }
        }

        static if (Compression_Level == 1 || Compression_Level == 2) {
            uint hashFunc(uint i) {
                static if (Compression_Level == 1) {
                    return ((i >> 12) ^ i) & (Hash_Values - 1);

                } else if (Compression_Level == 2) {
                    return (((i >> 9) ^ (i >> 13) ^ i) & (Hash_Values - 1));
                }
            }

            size_t lastHashed;
            void updateHash(int i) {
                static if (Compression_Level == 1) {
                    ubyte temp[4];
                    outDataIn.seek(i);
                    outDataIn.read(temp[0 .. 3]);
                    uint fetch = *cast(uint*)temp.ptr;
                    uint h = hashFunc(fetch);
                    hashTable[h].offset[0] = i;
                    if (log.enabled(log.Trace)) log.trace("output: h[{:x8}] = {:x8}", h, i);
                    hashCounter[h] = 1;

                    if (log.enabled(log.Trace)) log.trace("fetchinup: {:x8}", fetch);

                } else static if (Compression_Level == 2) {
                    ubyte temp[4];
                    outDataIn.seek(i);
                    outDataIn.read(temp[0 .. 3]);
                    uint fetch = *cast(uint*)temp.ptr;
                    uint h = hashFunc(fetch);
                    if (log.enabled(log.Trace)) log.trace("output: h[{:x8}] = {:x8}", h, i);
                    hashTable[h].offset[hashCounter[h] & (Pointers - 1)] = i;
                    ++hashCounter[h];

                    if (log.enabled(log.Trace)) log.trace("fetchinup: {:x8}", fetch);
                }
            }
            void updateHashUpto(size_t limit) {
                if (log.enabled(log.Trace)) log.trace("last hashed +1 {:x8} dst-3 {:x8}", lastHashed + 1, limit);
                outDataOut.flush;
                if (!lastHashed) {
                    if (log.enabled(log.Trace)) log.trace("cur: {:x8}", lastHashed);
                    updateHash(0);
                }
                while (lastHashed < limit) {
                    ++lastHashed;
                    if (log.enabled(log.Trace)) log.trace("cur: {:x8}", lastHashed);
                    updateHash(lastHashed);
                }
            }
        }

        size_t writtenBytes;
        while (1) {
            getCodeword;

            outDataOut.flush;
            if (log.enabled(log.Trace)) log.trace("curpos : {:x8} {:x8} {}", outDataOut.seek(0, IOStream.Anchor.Current), state, bitCount);

            // initialized with zeroes
            ubyte temp[4];

            //uint fetch = cast(uint)(inData.getInt);
            //if (log.enabled(log.Trace)) log.trace("fetch {:x8}", fetch);
            uint stateBit = state & 1;
            state >>= 1;
            
            if (stateBit) {
                if (log.enabled(log.Trace)) log.trace("got bit");
                uint matchLen = void;
                static if (Compression_Level == 1) {
                    inData.read(temp[0 .. 3]);
                    uint fetch = *cast(uint*)temp.ptr;
                    uint hash = (fetch >> 4) & 0xfff;
                    uint off2 = hashTable[hash].offset[0];
                    if (log.enabled(log.Trace)) log.trace("hash: {:x4}", hash);

                    if ((fetch & 0xf) != 0) {
                        matchLen = (fetch & 0xf) + 2;
                        inData.seek(-1, IOStream.Anchor.Current);

                    } else {
                        matchLen = temp[2];
                    }

                } else static if (Compression_Level == 2) {
                    inData.read(temp[0 .. 3]);
                    uint fetch = *cast(uint*)temp.ptr;
                    uint hash = (fetch >> 5) & 0x7ff;
                    uint off2 = hashTable[hash].offset[fetch & 0x3];
                    if (log.enabled(log.Trace)) log.trace("hash: {:x4}", hash);

                    if ((fetch & 0x1c) != 0) {
                        matchLen = ((fetch >> 2) & 0x7) + 2;
                        inData.seek(-1, IOStream.Anchor.Current);

                    } else {
                        matchLen = temp[2];
                    }

                } else static if (Compression_Level == 3) {
                    inData.read(temp[0 .. 2]);
                    uint fetch = *cast(uint*)temp.ptr;

                    uint offset = void;
                    
                    // 8 | 2 codebits, 6 off bits, const match
                    if ((fetch & 0x3) == 0) {
                        offset = temp[0] >> 2;
                        matchLen = 3;
                        inData.seek(-1, IOStream.Anchor.Current);
                        if (log.enabled(log.Info)) log.info("1");

                    // 16 | 2 codebits, 14 off bits, const match
                    } else if ((fetch & 0x2) == 0) {
                        offset = cast(ushort)fetch >> 2;
                        matchLen = 3;
                        if (log.enabled(log.Info)) log.info("2a");

                    // 16 | 2 code-bits, 10 off bits, 4 match bits
                    } else if ((fetch & 0x1) == 0) {
                        offset = cast(ushort)fetch >> 6;
                        matchLen = ((fetch >> 2) & 0xf) + 3;
                        if (log.enabled(log.Info)) log.info("2a");

                    //  24 | 2 code bits, 17 off bits, 5 match bits
                    } else if ((fetch & 0x7f) != 3) {
                        inData.read(temp[2 .. 3]);
                        fetch = *cast(uint*)temp.ptr;

                        // fetch has max value of 0xffffff so this is ok
                        offset = fetch >> 7;
                        matchLen = ((fetch >> 2) & 0x1f) + 2;
                        if (log.enabled(log.Info)) log.info("3");

                    // 32 | 7 code bits (0000011), 17 off bits, 8 match bits
                    } else {
                        inData.read(temp[2 .. 4]);
                        fetch = *cast(uint*)temp.ptr;

                        offset = (fetch >> 15);
                        matchLen = ((fetch >> 7) & 0xff) + 3;
                        if (log.enabled(log.Info)) log.info("4");
                    }
                    outDataOut.flush;

                    //uint off2 = outDataOut.seek(0, IOStream.Anchor.Current) - offset;
                }
                
                if (log.enabled(log.Trace)) log.trace("match: {:x4}", matchLen);

                outDataOut.flush;
                static if (Compression_Level == 1 || Compression_Level == 2) {
                    long off = outDataOut.seek(0, IOStream.Anchor.Current) - off2;
                    if (log.enabled(log.Trace)) log.trace("off: {:x4} back {:x8}", off2, off);

                } else {
                    long off = offset;
                    if (log.enabled(log.Trace)) log.trace("off: {:x4} ", off);
                }

                writeBack(outDataIn, outDataOut, off, matchLen);
                writtenBytes += matchLen;

                static if (Compression_Level == 1 || Compression_Level == 2) {
                    updateHashUpto(writtenBytes);
                    lastHashed = writtenBytes - 1; // seems kinda strange...
                }

            } else {
                if (log.enabled(log.Trace)) log.trace("no bit");
                if (writtenBytes < unpackSize -1 - Unconditional_Matchlen - Uncompressed_End) {
                    //if (log.enabled(log.Trace)) log.trace("all ok");

                    int bs = !(state & 1) * (!(state&7) + ((4 - (state&2))>>1));

                    inData.read(temp[0 .. bs+1]);
                    outDataOut.write(temp[0 .. bs+1]);
                    uint bitShift[] = [ 3, 0, 1, 0, 2, 0, 1, 0 ];
                    if (log.enabled(log.Trace)) log.trace("bitshift: {:x} {} vs {}", state&7, bitShift[state & 7], bs);
                    state >>= bs;

                    writtenBytes += bs+1;
                    static if (Compression_Level == 1 || Compression_Level == 2) {
                        updateHashUpto(writtenBytes - 3);
                    }

                } else {

                    while (writtenBytes < unpackSize) {
                        if (1 == state) {
                            inData.getInt;
                            state = 1 << 31;
                        }

                        outDataOut.putByte(inData.getByte);
                        writtenBytes++;
                        state >>= 1;
                    }
                    outDataOut.flush;

                    //updateHashUpto(writtenBytes - 3)
                    break;
                }
            }
        }
    }

    public:

    static const int Buffer_Counter = 8;
    static const int Streaming_Buffer = 0;

    static const int Unconditional_Matchlen = 6;
    static const int Uncompressed_End = 4;

    // 1, 4, 16
    static const int Pointers = 1 << (1 << (Compression_Level - 1));
    struct HashDecompress {
        ulong offset[Pointers];
    }

    static if (Compression_Level == 1) {
        static const int Hash_Values = 4096;
        HashDecompress hashTable[Hash_Values];
        ubyte hashCounter[Hash_Values];

    } else static if (Compression_Level == 2) {
        static const int Hash_Values = 2048;
        HashDecompress hashTable[Hash_Values];
        ubyte hashCounter[Hash_Values];

    } else static if (Compression_Level == 3) {
        static const int Hash_Values = 4096;
    }

}
