module compress.model.IDecompressor;

private import tango.io.model.IConduit;

interface IDecompressor
{
        void decompressStream(InputStream inStream, IConduit outStream, int unpackedLength = -1);
}
