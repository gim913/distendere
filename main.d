//import compress.Aplib;
//import compress.Lzss;
//import compress.BriefLz;
import compress.QuickLz;

import tango.io.Stdout;
import tango.io.device.File;
import tango.io.device.FileMap;

import tango.util.log.Log;
import tango.util.log.Config;

int main(char[][] args)
{
    if (args.length != 4) {
        Stdout.formatln ("{} d fileIn fileOut", args[0]);
        return 1;
    }

    foreach (ref Logger l; Log.hierarchy) {
        l.level = Log.root.Warn;
    }
    //Log.lookup("compress.QuickLz").level = Log.root.Info;

    auto inFile = new FileMap(args[2], File.ReadExisting);
    auto file = new File(args[3], File.ReadWriteCreate);

    /+
    auto aplib = new Aplib!(8);
    
    inFile.seek(0x18);
    aplib.decompressStream(inFile, file);
    +/

    /+
    auto lzss = new Lzss!();
    lzss.decompressStream(inFile, file);
    +/

    /+
    auto briefLz = new BriefLz;
    briefLz.decompressStream(inFile, file);
    +/

    auto qlz = new QuickLz!(3);

    uint r = 0x7800;
    Stdout.formatln ("{:x}", r).newline;
    qlz.decompressStream(inFile, file, r);

    return 0;
}
