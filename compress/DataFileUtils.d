module compress.DataFileUtils;

private import tango.io.stream.Data;
private import tango.io.model.IConduit;
private import tango.util.log.Log;

private Logger log;

static this()
{
    log = Log.lookup ("compress.DataFileUtils");
}

void writeBack(DataInput outDataIn, DataOutput outDataOut, long off, int len) {
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

