#!/bin/bash

echo 'Checking preconditions...'

if [ "$1" = "" ]; then
    echo 'Please provide the directory containing the NameNode metadata'
    exit 1
fi

FSIMAGE_DIR=$(readlink -m $1)
if [ ! -d "$FSIMAGE_DIR/current" ]; then
    echo Provided directory must contain the '"current"' directory with the NN metadata
    exit 1
fi

source /usr/bin/bigtop-detect-javahome 2>/dev/null
if [[ -z "$JAVA_HOME" ]]
then
  if [[ -d "/usr/java/latest" ]]
  then
    export JAVA_HOME="/usr/java/latest"
  elif [[ -d "/usr/java/default" ]]
  then
    export JAVA_HOME="/usr/java/default"
  else
    echo "Could not determine location of JDK to run script."
    echo "Please export JAVA_HOME manually and then re-run script."
    exit 1
  fi
fi

echo 'Preconditions OK'

#echo 'Getting availble hadoop versions'
#OPTIONS=$(curl -s https://archive.apache.org/dist/hadoop/common/ | egrep -o "hadoop-[^\/]*" | sort -u)
#if [[ ! -z "${param// }" ]]; then
#  echo "Error in getting hadoop versions - check if https://archive.apache.org/dist/hadoop/common/ site is reachable."
#  exit 1
#fi

echo 'Please select a version!'
OPTIONS=$(ls patches | cut -c -17)
select opt in $OPTIONS; do
  if [ ! "$opt" = "" ]; then
    VERSION=$opt
    break
  fi
  echo Invalid choice
done

VERSIONNUMBER=${VERSION#*-}

### Checking if patched jar is available
if [ ! -f patches/$VERSION.jar ]; then
  echo "Could not find patched jar for $VERSIONNUMBER!"
  exit 1
fi

### Getting the released hadoop version
SCRIPT_DIR=$(dirname $0)
HADOOPVERSION=${VERSION/"-hdfs"/""}
if [ ! -d $HADOOPVERSION ]; then
  echo "Downloading and extracting HDFS $HADOOPVERSION tarball..."
  wget -q https://archive.apache.org/dist/hadoop/common/$HADOOPVERSION/$HADOOPVERSION.tar.gz
  if [ $? -ne 0 ]; then
    echo "Couldn/'t download $HADOOPVERSION."
    exit 1
  fi
  tar xf $HADOOPVERSION.tar.gz
fi

while true; do
    read -p "Do you want to repair the image (y/n)? " yn
    case $yn in
        [Yy]* )
          echo "Replacing the HDFS jars in tarball to run with fix."
          mv $HADOOPVERSION/share/hadoop/hdfs/$VERSION.jar{,.orig}
          cp $SCRIPT_DIR/patches/$VERSION.jar $HADOOPVERSION/share/hadoop/hdfs/
          break
          ;;
        [Nn]* )
          echo "Just checking if the NN can start up."
          break
          ;;
        * ) echo "Please answer y or n.";;
    esac
done

echo "Configuring HDFS to run over provided dfs.namenode.name.dir = ${FSIMAGE_DIR}"
echo "<configuration><property><name>fs.defaultFS</name><value>hdfs://localhost</value></property></configuration>" > $HADOOPVERSION/etc/hadoop/core-site.xml
echo "<configuration><property><name>dfs.namenode.name.dir</name><value>$FSIMAGE_DIR</value></property></configuration>" > $HADOOPVERSION/etc/hadoop/hdfs-site.xml
### TODO configure memory allocation
echo "export HADOOP_NAMENODE_OPTS=\"-Xmx4g -Xms3g \$HADOOP_NAMENODE_OPTS\"" >> $HADOOPVERSION/etc/hadoop/hadoop-env.sh
export HADOOP_CONF_DIR=$HADOOPVERSION/etc/hadoop/

echo "Launching NameNode..."
$HADOOPVERSION/bin/hdfs namenode 2> namenode.err > namenode.out &
NN_PID=$!
until $HADOOPVERSION/bin/hdfs dfsadmin -report 2> /dev/null > /dev/null
do
  if ps -p $NN_PID > /dev/null
  then
    echo "Waiting on NameNode [$NN_PID] to come up..."
    sleep 3s
  else
    echo "NameNode failed to come up."
    if [ $(grep -o "File system image contains an old layout version" namenode.err | wc -l) -ge 1 ]; then
      echo 'The chosen version of hadoop is too new!'

      while true; do
          read -p "Do you want to upgrade the namenode (y/n)? " yn
          case $yn in
              [Yy]* )
                $HADOOPVERSION/bin/hdfs namenode -upgrade 2> namenode.err > namenode.out &
                NN_PID=$!
                until $HADOOPVERSION/bin/hdfs dfsadmin -report 2> /dev/null > /dev/null
                do
                  if ps -p $NN_PID > /dev/null
                  then
                    echo "Waiting on NameNode [$NN_PID] to come up..."
                    sleep 3s
                  else
                    echo "NameNode failed to come up."
                    echo "Dumping tails of namenode.err and namenode.out..."
                    echo
                    tail -100 namenode.err
                    tail -100 namenode.out
                    exit 1
                  fi
                done
                break
                ;;
              [Nn]* )
                exit 1
                ;;
              * ) echo "Please answer y or n.";;
          esac
      done
      break
    fi
    if [ $(grep -o "Unexpected version of storage directory" namenode.err | wc -l) -ge 1 ]; then
      echo 'The chosen version of hadoop is too old!'
      exit 1
    fi
    echo "Dumping tails of namenode.err and namenode.out..."
    echo
    tail -100 namenode.err
    tail -100 namenode.out
    exit 1
  fi
done

echo "Saving namespace to generate fixed image files..."
$HADOOPVERSION/bin/hdfs dfsadmin -saveNamespace 2>/dev/null >/dev/null
echo
echo "**************************************"
echo
echo "Work done! Fixed images available now."
echo
echo "The fixed fsimage file(s) from $FSIMAGE_DIR:"
echo $(ls -rt $FSIMAGE_DIR/current/fsimage* | tail -2)
echo
echo "**************************************"

echo "Stopping the NameNode and cleaning up!"
kill $NN_PID 2> /dev/null > /dev/null
rm -rf $HADOOPVERSION $HADOOPVERSION.tar.gz

while true; do
    read -p "Wish to see the repairs (y/n)? " yn
    case $yn in
        [Yy]* ) grep --color=always 'PATCHED:' namenode.err; break;;
        [Nn]* ) break;;
        * ) echo "Please answer y or n.";;
    esac
done
