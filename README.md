# hadoop-hdfs-fsimage-fixer
## Introduction
This repo is intended to give help resolving HDFS NameNode's FSImage corruption issues. To learn more about the issue read the *FSImage corruption* part.

### Requirements
Internet access is required to run the script (downloading the released hadoop version from the apache website), and

Obviously the corrupt FSImage and the associated md5 file is also necessary contained in a directory named "current".

Installed Java is also required by the program.

**WARNING: running the script will essentially starts a NameNode, so it may consume a lot of memory and have high CPU usage.**

### Disclaimer
Always backup the NN's *current/* directory.

**WARNING: running the tool may result in data loss.**

Use this tool for your own responsibility.

#### Java OutOfMemory error
It might happen, that the Java VM runs out of memory. Currently the only way you can surpass this is to modify the memory flags in the script. (`-Xmx4g -Xms3g` flags)

## FSImage corruption
FileSystemImage (FSImage) is the metadata storage layer of the Hadoop Distributed File System (HDFS). It's corruption can happen in various cases - some of which is still of unknown origin. Since it's still one of the single point of failure in the HDFS (without the metadata, all the files are unavailable), this type of error considered fatal.

The tool is not intended to recover the errors, but to provide a working FSImage (so the NN not fails during startup process).

### Stack trace
We consider NullPointerException encountered during NameNode startup like this

```
ERROR namenode.NameNode: Failed to start namenode.
java.lang.NullPointerException
        at org.apache.hadoop.hdfs.server.namenode.INodeDirectory.addChild(INodeDirectory.java:531)
        at org.apache.hadoop.hdfs.server.namenode.FSImageFormatPBINode$Loader.addToParent(FSImageFormatPBINode.java:252)
        at org.apache.hadoop.hdfs.server.namenode.FSImageFormatPBINode$Loader.loadINodeDirectorySection(FSImageFormatPBINode.java:202)
        at org.apache.hadoop.hdfs.server.namenode.FSImageFormatProtobuf$Loader.loadInternal(FSImageFormatProtobuf.java:261)
        at org.apache.hadoop.hdfs.server.namenode.FSImageFormatProtobuf$Loader.load(FSImageFormatProtobuf.java:180)
        at org.apache.hadoop.hdfs.server.namenode.FSImageFormat$LoaderDelegator.load(FSImageFormat.java:226)
        at org.apache.hadoop.hdfs.server.namenode.FSImage.loadFSImage(FSImage.java:929)
        at org.apache.hadoop.hdfs.server.namenode.FSImage.loadFSImage(FSImage.java:913)
        at org.apache.hadoop.hdfs.server.namenode.FSImage.loadFSImageFile(FSImage.java:732)
        at org.apache.hadoop.hdfs.server.namenode.FSImage.loadFSImage(FSImage.java:668)
        at org.apache.hadoop.hdfs.server.namenode.FSImage.recoverTransitionRead(FSImage.java:281)
        at org.apache.hadoop.hdfs.server.namenode.FSNamesystem.loadFSImage(FSNamesystem.java:1061)
        at org.apache.hadoop.hdfs.server.namenode.FSNamesystem.loadFromDisk(FSNamesystem.java:765)
        at org.apache.hadoop.hdfs.server.namenode.NameNode.loadNamesystem(NameNode.java:584)
        at org.apache.hadoop.hdfs.server.namenode.NameNode.initialize(NameNode.java:643)
        at org.apache.hadoop.hdfs.server.namenode.NameNode.<init>(NameNode.java:810)
        at org.apache.hadoop.hdfs.server.namenode.NameNode.<init>(NameNode.java:794)
        at org.apache.hadoop.hdfs.server.namenode.NameNode.createNameNode(NameNode.java:1487)
        at org.apache.hadoop.hdfs.server.namenode.NameNode.main(NameNode.java:1553)
INFO util.ExitUtil: Exiting with status 1
```

## Usage
### Simple start
To run this tool just run the main script by

	./hadoop-hdfs-fsimage-fixer.sh <dir>

also give the path of the NameNode's current directory as a parameter.

For intended usage see the *Recommended steps for recovery* part.

### Recommended steps for recovery
1. Backup the NN's *current/* directory.
2. Check if latest fsimage is indeed corrupt:
	1. Run the script, and when prompted, answer no to repairing.
	2. Technically this starts the NN, and if the FSImage is corrupt, will fail with NPE.
```
Checking preconditions...
Preconditions OK
Please select a version!
1) hadoop-hdfs-2.5.0    5) hadoop-hdfs-2.7.6   9) hadoop-hdfs-2.9.1
2) hadoop-hdfs-2.5.2    6) hadoop-hdfs-2.7.7  10) hadoop-hdfs-3.0.2
3) hadoop-hdfs-2.6.0    7) hadoop-hdfs-2.8.4  11) hadoop-hdfs-3.0.3
4) hadoop-hdfs-2.6.5    8) hadoop-hdfs-2.9.0  12) hadoop-hdfs-3.1.0
#? 12
Downloading and extracting HDFS hadoop-3.1.0 tarball...
Do you want to repair the image (y/n)? n
Waiting on NameNode [109] to come up...
Waiting on NameNode [109] to come up...
NameNode failed to come up.
Dumping tails of namenode.err and namenode.out...
...
java.lang.NullPointerException
	at org.apache.hadoop.hdfs.server.namenode.INodeDirectory.addChild(INodeDirectory.java:567)
    at ...
```
3. If you see similar stack trace as above, the FSImage is corrupt and you can repair it (otherwise there is nothing to do)
	1. Delete the *current/* directory and the *previous/* possibly created directory by the NN in the folder provided as the script parameter
	2. Run the script, and when prompted, answer yes to repairing.
	3. Wait for the script to finish, if the repair succeeds you can see the ignored nodes by answering yes when prompted.

```
...
Waiting on NameNode [109] to come up...
Saving namespace to generate fixed image files...

**************************************

Work done! Fixed images available now.

The fixed fsimage file(s) from /:
/current/fsimage_0000000000000001658.md5 /current/fsimage_0000000000000001658

**************************************
Stopping the NameNode and cleaning up!
Wish to see the repairs (y/n)? y
2018-08-06 03:54:52,693 WARN namenode.FSImageFormatPBINode: PATCHED: Skipping null INode in loadINodeDirectorySection: id 107 in parent p id 58
...
```
The fixed image with the md5 file is the output of the script - copy that to the current folder of the production NN.

#### Upgrade
It might happen that the FSImage has different version number than the selected hadoop version's FSImage reader. In this case you can either select other hadoop version (if there's any appropriate), or just simply answer yes when asked to upgrade.
