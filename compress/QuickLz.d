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
            if (log.enabled(log.Trace)) { 
                log.trace("in decompress()");
            }

        }
}
