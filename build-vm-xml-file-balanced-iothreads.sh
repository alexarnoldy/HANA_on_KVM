#!/bin/bash

##### NEED TO TEST FOR XMLSTARLET (AKA XML), VIRT-INSTALL AND VIRT-XML 
## Script to create VM XML file, including vCPU, emulator, IOThread and NUMA node pinnings

##### Uncomment and set the following three variables to bypass the input phase of the script
#VM_NAME=test
#MEMORY=4
#WORKING_DIR=/tmp/my-test-dir
#### Files required to be in the working directory are:
####	VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS
####	ALL_NUMA_NODES_UNIQ
####	ALL_NUMA_NODES_COMMA_SEPARATED
####	VM_CPU_CORES_EMULATOR
####	VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS
####	VM_CPU_REMAINING_COMMA_SEPARATED

RED='\033[0;31m'
LBLUE='\033[1;36m'
NC='\033[0m'

##### Set the WORKING_DIR as the single command line option, which is the fully qualified pathname of a directory. 
##### Then will test to see if it is null (around line 150). 
##### If null, run func_gather_and_process_input (), which will reset WORKING_DIR to a directory named after the PID of the script. 
##### If not-null, will use values from the files in the named (and existing) directory.
##### DONE: Create the .var files from the gathered input (on a null run)
##### TODO: 1) Set the variables from the .var files. 2) Separate the input loop from the file generating loop.
WORKING_DIR=`echo $1`

func_gather_and_process_input () {
WORKING_DIR=/tmp/$$

mkdir -p $WORKING_DIR

echo -e "    Enter the ${LBLUE}NAME${NC} of the VM:"
read VM_NAME
	## Need to populate the file below for future non-interactive runs. 
echo $VM_NAME > $WORKING_DIR/VM_NAME.var
echo ""
echo ""
#echo -e "    Enter the absolute path name to place the output file:"
#read PATH_TO_OUTPUT_FILE
FILE_LOCATION=$WORKING_DIR/$VM_NAME.xml
echo ""
echo -e "    ${LBLUE}The final VM XML will be: $FILE_LOCATION${NC}"
echo ""
echo ""

## New method to specify cores on a per NUMA node basis
lscpu | grep ^"NUMA node"." " | awk -F, '{print$1}' | sed 's/A\ /A_/g' | sed 's/CPU(s)//' > $WORKING_DIR/ALL_NUMA_NODES_WITH_CPU_CORES
COUNTER=1
while [  $COUNTER -le $LINES ]
do 
	THIS_LINE=`head  -$COUNTER $WORKING_DIR/ALL_NUMA_NODES_WITH_CPU_CORES | tail -1`
	THIS_NUMA_NODE=`echo $THIS_LINE | awk '{print$1}'`
## BEGIN ## Gather cores for the VM
	func_use_cores_from_this_NUMA_node () {
	echo -e "    Enter the ${LBLUE}LAST${NC} CPU to be allocated to this VM:"
	read END
	## Need to populate the file below for future non-interactive runs. 
	echo $END > $WORKING_DIR/END_$THIS_NUMA_NODE.var
## END ## Gather cores for the VM
## BEGIN ## Iterate through the cores to find the hyper-thread siblings
	START=`cat $WORKING_DIR/START_$THIS_NUMA_NODE.var`
	END=`cat $WORKING_DIR/END_$THIS_NUMA_NODE.var`
	cat /dev/null > $WORKING_DIR/VM_CPU_CORES_ITERATED_$THIS_NUMA_NODE
	while [ $START -le $END ]; do  echo $START >> $WORKING_DIR/VM_CPU_CORES_ITERATED_$THIS_NUMA_NODE; START=$(($START+1));done
	cat /dev/null > $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_$THIS_NUMA_NODE

	for EACH in `cat $WORKING_DIR/VM_CPU_CORES_ITERATED_$THIS_NUMA_NODE`; do cat /sys/devices/system/cpu/cpu$EACH/topology/thread_siblings_list >> $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_$THIS_NUMA_NODE; done
	cat $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_$THIS_NUMA_NODE | sort -n | uniq > $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ_$THIS_NUMA_NODE
## END ## Iterate through the cores to find the hyper-thread siblings
## BEGIN ## Iterate through emulator threads
	func_gather_cores_for_emulator_threads () {
	EMULATOR_COUNT=`cat $WORKING_DIR/EMULATOR_COUNT_$THIS_NUMA_NODE.var`
	cat /dev/null > $WORKING_DIR/VM_CPU_CORES_EMULATOR_$THIS_NUMA_NODE
	head -`echo $EMULATOR_COUNT` $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ_$THIS_NUMA_NODE > $WORKING_DIR/VM_CPU_CORES_EMULATOR_$THIS_NUMA_NODE
	tr '\n' , < $WORKING_DIR/VM_CPU_CORES_EMULATOR_$THIS_NUMA_NODE > $WORKING_DIR/VM_CPU_CORES_EMULATOR.tmp
	mv $WORKING_DIR/VM_CPU_CORES_EMULATOR.tmp $WORKING_DIR/VM_CPU_CORES_EMULATOR_$THIS_NUMA_NODE
	}
## END ## Iterate through emulator threads
## BEGIN ## Gather cores for emulator threads
	echo -e "    How many CPU cores from this NUMA node will be used for ${LBLUE}QEMU Emulator threads${NC} (Just press Enter to skip this NUMA node)?"
	read EMULATOR_COUNT
## END ## Gather cores for emulator threads
	## Need to populate the file below for future non-interactive runs. Need to move this inside the function.
	echo $EMULATOR_COUNT > $WORKING_DIR/EMULATOR_COUNT_$THIS_NUMA_NODE.var
	[ -n "$EMULATOR_COUNT" ] && func_gather_cores_for_emulator_threads
## END ## Establish cores for emulator threads
## BEGIN ## Establish cores for iothreads
	## Same as emulator but replace EMULATOR with IOTHREAD and change head statement
	func_gather_cores_for_iothreads () {
	cat /dev/null > $WORKING_DIR/VM_CPU_CORES_IOTHREADS_$THIS_NUMA_NODE
	head -`echo $(( $EMULATOR_COUNT + $IOTHREAD_COUNT ))` $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ_$THIS_NUMA_NODE | tail -`echo $IOTHREAD_COUNT` > $WORKING_DIR/VM_CPU_CORES_IOTHREADS_$THIS_NUMA_NODE
	tr '\n' , < $WORKING_DIR/VM_CPU_CORES_IOTHREADS_$THIS_NUMA_NODE > $WORKING_DIR/VM_CPU_CORES_IOTHREADS.tmp
	mv $WORKING_DIR/VM_CPU_CORES_IOTHREADS.tmp $WORKING_DIR/VM_CPU_CORES_IOTHREADS_$THIS_NUMA_NODE
	tr , '\n' < $WORKING_DIR/VM_CPU_CORES_IOTHREADS_$THIS_NUMA_NODE > $WORKING_DIR/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS_$THIS_NUMA_NODE
	}
	echo -e "    How many CPU cores from this NUMA node will be used for ${LBLUE}QEMU  IOThreads${NC} (Just press Enter to skip this NUMA node)?"
	read IOTHREAD_COUNT
	## Need to populate the file below for future non-interactive runs. Need to move this inside the function.
	echo $IOTHREAD_COUNT > $WORKING_DIR/IOTHREAD_COUNT_$THIS_NUMA_NODE.var
	[ -n "$IOTHREAD_COUNT" ] && func_gather_cores_for_iothreads
## END ## Establish cores for iothreads
## BEGIN ## Establish reamining cores for the VM
	tail -n +`echo $(( $EMULATOR_COUNT + $IOTHREAD_COUNT + 1 ))` $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ_$THIS_NUMA_NODE > $WORKING_DIR/VM_CPU_CORES_REMAINING_$THIS_NUMA_NODE
	## This gets rid of all commas. Result is a single column of LCPUs
	tr , '\n' < $WORKING_DIR/VM_CPU_CORES_REMAINING_$THIS_NUMA_NODE > $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS_$THIS_NUMA_NODE
## END ## Establish reamining cores for the VM
	}
	echo "These are the CPUs on $THIS_LINE" 
	echo -e "    Enter the ${LBLUE}FIRST${NC} CPU from this NUMA node to be allocated to this VM (Just press Enter to skip this NUMA node):" 
	read START
	## Need to populate the file below for future non-interactive runs. Need to move this inside the function.
	echo $START > $WORKING_DIR/START_$THIS_NUMA_NODE.var
	## If the value of $START is non-null, run the above function to gather CPU info for this NUMA node
	[ -n "$START" ] && func_use_cores_from_this_NUMA_node
	let COUNTER=COUNTER+1
	LINES=`wc -l $WORKING_DIR/ALL_NUMA_NODES_WITH_CPU_CORES | awk '{print$1}'`
done


#### BEGIN #### Consolidate lists from all NUMA nodes 

## Consolidate cores from each NUMA node into single list of cores to be used for QEMU emulator threads
cat $WORKING_DIR/VM_CPU_CORES_EMULATOR_* > $WORKING_DIR/VM_CPU_CORES_EMULATOR
VM_CPU_CORES_EMULATOR=`cat $WORKING_DIR/VM_CPU_CORES_EMULATOR`
echo "${VM_CPU_CORES_EMULATOR::-1}" > $WORKING_DIR/VM_CPU_CORES_EMULATOR.tmp
mv $WORKING_DIR/VM_CPU_CORES_EMULATOR.tmp $WORKING_DIR/VM_CPU_CORES_EMULATOR

## Consolidate cores from each NUMA node into single list of cores to be used for QEMU IOThreads
cat $WORKING_DIR/VM_CPU_CORES_IOTHREADS_* > $WORKING_DIR/VM_CPU_CORES_IOTHREADS
VM_CPU_CORES_IOTHREADS=`cat $WORKING_DIR/VM_CPU_CORES_IOTHREADS`
echo "${VM_CPU_CORES_IOTHREADS::-1}" > $WORKING_DIR/VM_CPU_CORES_IOTHREADS.tmp
mv $WORKING_DIR/VM_CPU_CORES_IOTHREADS.tmp $WORKING_DIR/VM_CPU_CORES_IOTHREADS
cat $WORKING_DIR/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS_* > $WORKING_DIR/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS

## Consolidate cores from each NUMA node into single list of cores to be used for vCPUs
## Need three outputs: vCPUs+Siblings in a single column, vCPUs+Siblings in comma separated list, a count of vCPUs

## vCPUs+Siblings in a single column
cat $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS_* > $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS

## vCPUs+Siblings in a comma separated list
VM_CPU_REMAINING_COMMA_SEPARATED=`tr '\n' , < $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS`
echo "${VM_CPU_REMAINING_COMMA_SEPARATED::-1}" > $WORKING_DIR/VM_CPU_REMAINING_COMMA_SEPARATED

#### END #### Consolidate lists from all NUMA nodes 



echo -e "    Enter the amount of ${LBLUE}MEMORY${NC} in GiB to be allocated to this VM:"
read MEMORY
	## Need to populate the file below for future non-interactive runs. 
echo $MEMORY > $WORKING_DIR/MEMORY.var
}

##### Test to run the input gathering function only if there is no command line option provided
[ -z "$WORKING_DIR" ] && func_gather_and_process_input

## Set VM_NAME in both null and non-null runs
VM_NAME=`cat $WORKING_DIR/VM_NAME.var`

## Count of vCPUs
TOTAL_VCPUS=`wc -l $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS | awk '{print$1}'`
echo $TOTAL_VCPUS

####
## Beginning of creating the XML file
####
FILE_LOCATION=$WORKING_DIR/$VM_NAME.xml
virt-install --name $VM_NAME --memory $MEMORY --vcpu $TOTAL_VCPUS --disk none --pxe --print-xml 2 --dry-run > $FILE_LOCATION

#### Begin xml (xmlstarlet) updates to the base file created by virt-install
#### Use xml el -v <file> to see all fo the elements, attributes, and values #### 
#### Later will replace as many xmlstarlet commands with virt-xml commands as possible

## Add cputune, numatune and memoryBacking (plus hugepages) elements to the XML file
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain" --type elem -n "cputune" -v "" $FILE_LOCATION > $FILE_LOCATION.tmp 
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain" --type elem -n "numatune" -v "" $FILE_LOCATION > $FILE_LOCATION.tmp 
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain" --type elem -n "memoryBacking" -v "" $FILE_LOCATION > $FILE_LOCATION.tmp 
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain/memoryBacking" --type elem -n "hugepages" -v "" $FILE_LOCATION > $FILE_LOCATION.tmp 
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain/memoryBacking" --type elem -n "nosharepages" -v "" $FILE_LOCATION > $FILE_LOCATION.tmp 

## Configure hugepages as 1GiB
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain/memoryBacking/hugepages" --type elem -n "page size='1048576' unit='KiB'" -v "" $FILE_LOCATION > $FILE_LOCATION.tmp 

## Add vCPU pinning list to the XML file
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
COUNTER=1 
LINES=`wc -l $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS | awk '{print$1}'` 
while [  $COUNTER -le $LINES ] 
do 
	THIS_LINE=`head  -$COUNTER $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS | tail -1`
	xml ed --subnode "/domain/cputune" --type elem -n "vcpupin vcpu='`echo $(( $COUNTER - 1 ))`' cpuset='$THIS_LINE'" $FILE_LOCATION > $FILE_LOCATION.tmp
	mv $FILE_LOCATION.tmp $FILE_LOCATION
	let COUNTER=COUNTER+1
	LINES=`wc -l $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS | awk '{print$1}'`
done


## Add NUMA node pinning to the XML file
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
numactl --hardware | grep cpus | sed 's/node /node/' > $WORKING_DIR/NUMA_NODES_TO_CPUS
cat /dev/null > $WORKING_DIR/ALL_NUMA_NODES
for EACH in `cat $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS`
do 
	grep -w $EACH $WORKING_DIR/NUMA_NODES_TO_CPUS | awk -Fe '{print$2}' | awk '{print$1}' >> $WORKING_DIR/ALL_NUMA_NODES
done
sort $WORKING_DIR/ALL_NUMA_NODES | uniq > $WORKING_DIR/ALL_NUMA_NODES_UNIQ

## Process the list of NUMA nodes, removing the trailing comma
ALL_NUMA_NODES_UNIQ=`tr '\n' , < $WORKING_DIR/ALL_NUMA_NODES_UNIQ`
echo "${ALL_NUMA_NODES_UNIQ::-1}" > $WORKING_DIR/ALL_NUMA_NODES_COMMA_SEPARATED
## Set up the memory mode for all NUMA nodes
xml ed --subnode "/domain/numatune" --type elem -n "memory mode='strict' nodeset='`cat $WORKING_DIR/ALL_NUMA_NODES_COMMA_SEPARATED`'" $FILE_LOCATION > $FILE_LOCATION.tmp

## Add NUMA node pinning to the XML file
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
COUNTER=1 
LINES=`wc -l $WORKING_DIR/ALL_NUMA_NODES_UNIQ | awk '{print$1}'` 
while [  $COUNTER -le $LINES ] 
do 
	THIS_LINE=`head  -$COUNTER $WORKING_DIR/ALL_NUMA_NODES_UNIQ | tail -1`
	xml ed --subnode "/domain/numatune" --type elem -n "memnode cellid='`echo $(( $COUNTER - 1 ))`' mode='strict' nodeset='$THIS_LINE'" $FILE_LOCATION > $FILE_LOCATION.tmp
	mv $FILE_LOCATION.tmp $FILE_LOCATION
	let COUNTER=COUNTER+1
	LINES=`wc -l $WORKING_DIR/ALL_NUMA_NODES_UNIQ | awk '{print$1}'`
done




## Update hpet timer
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed -u "domain/clock/timer[@name='hpet' and @present='no']"/@present -v yes $FILE_LOCATION > $FILE_LOCATION.tmp

## Add emulatorpinning to the XML file
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain/cputune" --type elem -n "emulatorpin cpuset='`cat $WORKING_DIR/VM_CPU_CORES_EMULATOR`'" -v "" $FILE_LOCATION > $FILE_LOCATION.tmp

## Add total number of iothreads to the XML file
## virt-install and virt-xml don't seem to support iothreads
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain" --type elem -n "iothreads" -v "`wc -l $WORKING_DIR/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS | awk '{print$1}'`" $FILE_LOCATION > $FILE_LOCATION.tmp

## Add iothreadpinning list to the XML file
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
COUNTER=1 
LINES=`wc -l $WORKING_DIR/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS | awk '{print$1}'` 
while [  $COUNTER -le $LINES ] 
do 
	THIS_LINE=`head  -$COUNTER $WORKING_DIR/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS | tail -1`
	xml ed --subnode "/domain/cputune" --type elem -n "iothreadpin iothread='`echo $COUNTER`' cpuset='$THIS_LINE'" $FILE_LOCATION > $FILE_LOCATION.tmp
	mv $FILE_LOCATION.tmp $FILE_LOCATION
	let COUNTER=COUNTER+1
	LINES=`wc -l $WORKING_DIR/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS | awk '{print$1}'`
done

#### Begin virt-xml updates to the XML file

## vcpu placement
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
virt-xml --edit  --vcpu placement="static" < $FILE_LOCATION > $FILE_LOCATION.tmp
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
virt-xml --edit  --vcpu cpuset="`cat $WORKING_DIR/VM_CPU_REMAINING_COMMA_SEPARATED`" < $FILE_LOCATION > $FILE_LOCATION.tmp
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
virt-xml --edit --vcpu=`wc -l $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS | awk '{print$1}'` < $FILE_LOCATION > $FILE_LOCATION.tmp

## iothreads
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
#virt-xml --add-device iothreads=`wc -l $WORKING_DIR/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS | awk '{print$1}'` < $FILE_LOCATION > $FILE_LOCATION.tmp
#virt-xml --edit --iothreads=`wc -l $WORKING_DIR/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS | awk '{print$1}'` < $FILE_LOCATION > $FILE_LOCATION.tmp



mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
cat $FILE_LOCATION

####### virt-install --name test --memory 4096 --vcpu 2 --disk none --pxe --print-xml --dry-run --cputune vcpupin0.vcpu=0,vcpupin0.cpuset=2,vcpupin1.vcpu=1,vcpupin1.cpuset=8
