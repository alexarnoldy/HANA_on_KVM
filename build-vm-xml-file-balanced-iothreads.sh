#!/bin/bash

##### NEED TO TEST FOR XMLSTARLET (AKA XML), VIRT-INSTALL AND VIRT-XML 
## Script to create VM XML file, including vCPU, emulator, IOThread and NUMA node pinnings
## This script can be run interactively by executing with no arguments, or non-interactively by providing
## a single argument of an existing directory that contains files, each with the answer to the interactive questions.
## The required files in the existing directory are:
##	VM_NAME.var 		
##	MEMORY.var 	
##	START_NUMA_node0.var 		(plus the same for each additional NUMA node to be configured)
##	END_NUMA_node0.var 		(plus the same for each additional NUMA node to be configured)
##	EMULATOR_COUNT_NUMA_node0.var 	(plus the same for each additional NUMA node to be configured)
##	IOTHREAD_COUNT_NUMA_node0.var 	(plus the same for each additional NUMA node to be configured)
## If a feature is not to be configured for a NUMA nodes, i.e. emulator threads on 
## NUMA node 1, remove that file from the direcory. 
## DO NO USE 0 (ZERO) AS A VALUE IN INTERACTIVE OR NON-INTERACTIVE MODE

RED='\033[0;31m'
LBLUE='\033[1;36m'
NC='\033[0m'

if [ -z "$1" ]
then
      NONINTERACTIVE=true
else
      unset NONINTERACTIVE
fi
echo $NONINTERACTIVE

WORKING_DIR=`echo $1` 


func_gather_and_process_input () {

if [ -z "$NONINTERACTIVE" ]
then
	echo $1
	VM_NAME=`cat $WORKING_DIR/VM_NAME.var` 
else
	echo -e "    Enter the ${LBLUE}NAME${NC} of the VM:"
	read VM_NAME 
	WORKING_DIR=/tmp/$$ 
	mkdir -p $WORKING_DIR 
	echo $VM_NAME > $WORKING_DIR/VM_NAME.var
fi
echo ""
echo ""
FILE_LOCATION=$WORKING_DIR/$VM_NAME.xml
echo ""
#echo -e "    ${LBLUE}The final VM XML will be: $FILE_LOCATION${NC}"
echo ""
echo ""

## New method to specify cores on a per NUMA node basis
lscpu | grep ^"NUMA node"." " | awk -F, '{print$1}' | sed 's/A\ /A_/g' | sed 's/CPU(s)//' > $WORKING_DIR/ALL_NUMA_NODES_WITH_CPU_CORES
COUNTER=1
while [  $COUNTER -le $LINES ]
do 
	THIS_LINE=`head  -$COUNTER $WORKING_DIR/ALL_NUMA_NODES_WITH_CPU_CORES | tail -1`
	THIS_NUMA_NODE=`echo $THIS_LINE | awk '{print$1}'`
## BEGIN ## Function to gather and process core information from this NUMA node only if the START value is populated
## BEGIN ## Gather cores for the VM
	## Note that this function will be bypassed if there is not the START variable is not populated
	func_use_cores_from_this_NUMA_node () {
	if [ -z "$NONINTERACTIVE" ]
	then
		END=`cat $WORKING_DIR/END_$THIS_NUMA_NODE.var`
	else
		echo -e "    Enter the ${LBLUE}LAST${NC} CPU to be allocated to this VM:"
		read END 
		echo $END > $WORKING_DIR/END_$THIS_NUMA_NODE.var
	fi
## END ## Gather cores for the VM
## BEGIN ## Establish final hyper-thread sibling for vCPU to NUMA node mapping
	awk -F, '{print$2}' /sys/devices/system/cpu/cpu$END/topology/thread_siblings_list > $WORKING_DIR/VM_FINAL_HT_SIBLING_$THIS_NUMA_NODE
## END ## Establish final hyper-thread sibling for vCPU to NUMA node mapping
## BEGIN ## Iterate through the cores to find the hyper-thread siblings
	cat /dev/null > $WORKING_DIR/VM_CPU_CORES_ITERATED_$THIS_NUMA_NODE
	while [ $START -le $END ]; do  echo $START >> $WORKING_DIR/VM_CPU_CORES_ITERATED_$THIS_NUMA_NODE; START=$(($START+1));done
	cat /dev/null > $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_$THIS_NUMA_NODE

	for EACH in `cat $WORKING_DIR/VM_CPU_CORES_ITERATED_$THIS_NUMA_NODE`; do cat /sys/devices/system/cpu/cpu$EACH/topology/thread_siblings_list >> $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_$THIS_NUMA_NODE; done
	cat $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_$THIS_NUMA_NODE | sort -n | uniq > $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ_$THIS_NUMA_NODE
## END ## Iterate through the cores to find the hyper-thread siblings
## BEGIN ## Function to iterate through emulator threads
	func_gather_cores_for_emulator_threads () {
	cat /dev/null > $WORKING_DIR/VM_CPU_CORES_EMULATOR_$THIS_NUMA_NODE
	head -`echo $EMULATOR_COUNT` $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ_$THIS_NUMA_NODE > $WORKING_DIR/VM_CPU_CORES_EMULATOR_$THIS_NUMA_NODE
	tr '\n' , < $WORKING_DIR/VM_CPU_CORES_EMULATOR_$THIS_NUMA_NODE > $WORKING_DIR/VM_CPU_CORES_EMULATOR.tmp
	mv $WORKING_DIR/VM_CPU_CORES_EMULATOR.tmp $WORKING_DIR/VM_CPU_CORES_EMULATOR_$THIS_NUMA_NODE
	}
## END ## Function to iterate through emulator threads
## BEGIN ## Gather cores for emulator threads
	if [ -z "$NONINTERACTIVE" ]
	then
		EMULATOR_COUNT=`cat $WORKING_DIR/EMULATOR_COUNT_$THIS_NUMA_NODE.var`
	else
		echo -e "    How many CPU cores from this NUMA node will be used for ${LBLUE}QEMU Emulator threads${NC} (Just press Enter to skip this NUMA node)?" 
		read EMULATOR_COUNT 
		echo $EMULATOR_COUNT > $WORKING_DIR/EMULATOR_COUNT_$THIS_NUMA_NODE.var
	fi
## END ## Gather cores for emulator threads
## BEGIN ## Call function to iterate through emulator threads for null run
	[ -n "$EMULATOR_COUNT" ] && func_gather_cores_for_emulator_threads
## END ## Call function to iterate through emulator threads for null run
## BEGIN ## Function to iterate through iothreads
	## Very similar to emulator but replace EMULATOR with IOTHREAD and change head statement
	func_gather_cores_for_iothreads () {
	cat /dev/null > $WORKING_DIR/VM_CPU_CORES_IOTHREADS_$THIS_NUMA_NODE
	head -`echo $(( $EMULATOR_COUNT + $IOTHREAD_COUNT ))` $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ_$THIS_NUMA_NODE | tail -`echo $IOTHREAD_COUNT` > $WORKING_DIR/VM_CPU_CORES_IOTHREADS_$THIS_NUMA_NODE
	tr '\n' , < $WORKING_DIR/VM_CPU_CORES_IOTHREADS_$THIS_NUMA_NODE > $WORKING_DIR/VM_CPU_CORES_IOTHREADS.tmp
	mv $WORKING_DIR/VM_CPU_CORES_IOTHREADS.tmp $WORKING_DIR/VM_CPU_CORES_IOTHREADS_$THIS_NUMA_NODE
	tr , '\n' < $WORKING_DIR/VM_CPU_CORES_IOTHREADS_$THIS_NUMA_NODE > $WORKING_DIR/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS_$THIS_NUMA_NODE
	}
## END ## Function to iterate through iothreads
## BEGIN ## Gather cores for iothreads
	if [ -z "$NONINTERACTIVE" ]
	then
		IOTHREAD_COUNT=`cat $WORKING_DIR/IOTHREAD_COUNT_$THIS_NUMA_NODE.var`
	else
		echo -e "    How many CPU cores from this NUMA node will be used for ${LBLUE}QEMU  IOThreads${NC} (Just press Enter to skip this NUMA node)?" 
		read IOTHREAD_COUNT 
		echo $IOTHREAD_COUNT > $WORKING_DIR/IOTHREAD_COUNT_$THIS_NUMA_NODE.var
	fi
## END ## Gather cores for iothreads
## BEGIN ## Call function to iterate through iothreads for null run
	[ -n "$IOTHREAD_COUNT" ] && func_gather_cores_for_iothreads
## END ## Call function to iterate through iothreads for null run
## BEGIN ## Process reamining cores for the VM
	tail -n +`echo $(( $EMULATOR_COUNT + $IOTHREAD_COUNT + 1 ))` $WORKING_DIR/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ_$THIS_NUMA_NODE > $WORKING_DIR/VM_CPU_CORES_REMAINING_$THIS_NUMA_NODE
	## This gets rid of all commas. Result is a single column of LCPUs
	tr , '\n' < $WORKING_DIR/VM_CPU_CORES_REMAINING_$THIS_NUMA_NODE > $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS_$THIS_NUMA_NODE
## END ## Process reamining cores for the VM
	}
	## Note that the START variable must be populated for a NUMA node to enter the func_use_cores_from_this_NUMA_node function, both in null and non-null runs
	if [ -z "$NONINTERACTIVE" ]
	then
		START=`cat $WORKING_DIR/START_$THIS_NUMA_NODE.var`
	else
		echo "These are the CPUs on $THIS_LINE" 
		echo -e "    Enter the ${LBLUE}FIRST${NC} CPU from this NUMA node to be allocated to this VM (Just press Enter to skip this NUMA node):" 
		read START 
		echo $START > $WORKING_DIR/START_$THIS_NUMA_NODE.var
	fi
	## If the value of $START is non-null, run the above function to gather CPU info for this NUMA node
	[ -n "$START" ] && func_use_cores_from_this_NUMA_node
	let COUNTER=COUNTER+1
	LINES=`wc -l $WORKING_DIR/ALL_NUMA_NODES_WITH_CPU_CORES | awk '{print$1}'`
done


#### BEGIN #### Consolidate lists from all NUMA nodes for null and non-null runs

## Consolidate final hyper-thread siblings per NUMA node for vCPU to NUMA node mapping
cat $WORKING_DIR/VM_FINAL_HT_SIBLING_* > $WORKING_DIR/VM_FINAL_HT_SIBLING 2>/dev/null

## Consolidate cores from each NUMA node into single list of cores to be used for QEMU emulator threads
cat $WORKING_DIR/VM_CPU_CORES_EMULATOR_* > $WORKING_DIR/VM_CPU_CORES_EMULATOR 2>/dev/null
func_consolidate_emulator_thread_cores () {
VM_CPU_CORES_EMULATOR=`cat $WORKING_DIR/VM_CPU_CORES_EMULATOR`
echo "${VM_CPU_CORES_EMULATOR::-1}" > $WORKING_DIR/VM_CPU_CORES_EMULATOR.tmp
mv $WORKING_DIR/VM_CPU_CORES_EMULATOR.tmp $WORKING_DIR/VM_CPU_CORES_EMULATOR
}
[ `wc -l $WORKING_DIR/VM_CPU_CORES_EMULATOR | awk '{print$1}'` -gt 0 ] && func_consolidate_emulator_thread_cores

## Consolidate cores from each NUMA node into single list of cores to be used for QEMU IOThreads
cat $WORKING_DIR/VM_CPU_CORES_IOTHREADS_* > $WORKING_DIR/VM_CPU_CORES_IOTHREADS 2>/dev/null
func_consolidate_IO_thread_cores () {
VM_CPU_CORES_IOTHREADS=`cat $WORKING_DIR/VM_CPU_CORES_IOTHREADS`
echo "${VM_CPU_CORES_IOTHREADS::-1}" > $WORKING_DIR/VM_CPU_CORES_IOTHREADS.tmp
mv $WORKING_DIR/VM_CPU_CORES_IOTHREADS.tmp $WORKING_DIR/VM_CPU_CORES_IOTHREADS
cat $WORKING_DIR/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS_* > $WORKING_DIR/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS
}
[ `wc -l $WORKING_DIR/VM_CPU_CORES_IOTHREADS | awk '{print$1}'` -gt 0 ] && func_consolidate_IO_thread_cores

## Consolidate cores from each NUMA node into single list of cores to be used for vCPUs
## Need three outputs: vCPUs+Siblings in a single column, vCPUs+Siblings in comma separated list, a count of vCPUs

## vCPUs+Siblings in a single column
cat $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS_* > $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS

## vCPUs+Siblings in a comma separated list
VM_CPU_REMAINING_COMMA_SEPARATED=`tr '\n' , < $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS`
echo "${VM_CPU_REMAINING_COMMA_SEPARATED::-1}" > $WORKING_DIR/VM_CPU_REMAINING_COMMA_SEPARATED

#### END #### Consolidate lists from all NUMA nodes for null and non-null runs



if [ -z "$NONINTERACTIVE" ]
then
	MEMORY=`cat $WORKING_DIR/MEMORY.var`
else
	echo -e "    Enter the amount of ${LBLUE}MEMORY${NC} in GiB to be allocated to this VM:"
	read MEMORY
	echo $MEMORY > $WORKING_DIR/MEMORY.var
fi

}
## END ## Function to gather and process core information from this NUMA node only if the START value is populated

##### This lingering function is a byproduct of past requirements and will be removed in the near future
func_gather_and_process_input


## Set count of vCPUs in both null and non-null runs
TOTAL_VCPUS=`wc -l $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS | awk '{print$1}'`

####
## Beginning of creating the XML file
####
FILE_LOCATION=$WORKING_DIR/$VM_NAME.xml

########
##virt-install command for testing
########
virt-install --name $VM_NAME --memory $MEMORY --boot=uefi --description "$VM_NAME"  --vcpu $TOTAL_VCPUS --os-type=Linux --os-variant=sles12 --disk none --graphics none --print-xml --dry-run > $FILE_LOCATION
#virt-install --name $VM_NAME --memory $MEMORY --boot=uefi --description "$VM_NAME"  --vcpu $TOTAL_VCPUS --os-type=Linux --os-variant=sles12 --disk none --graphics vnc --location http://dist.suse.de/install/SLP/SLE-15-Installer-TEST/x86_64/DVD1/ --extra-args='autoyast=http://qa-css-hq.qa.suse.de/tftp/xml/profile/' --print-xml 2 --dry-run > $FILE_LOCATION
########
##virt-install command for creating a useable XML
########
#virt-install --name $VM_NAME --memory $MEMORY --boot=uefi --description "$VM_NAME"  --vcpu $TOTAL_VCPUS --os-type=Linux --os-variant=sles12 --disk /dev/disk/by-id/wwn-0x600000e00d29000000293db0007e0000,bus=virtio --graphics vnc --location http://dist.suse.de/install/SLP/SLE-15-Installer-TEST/x86_64/DVD1/ --extra-args='autoyast=http://qa-css-hq.qa.suse.de/tftp/xml/profile/' --print-xml 2 --dry-run > $FILE_LOCATION


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


## Add NUMA node pinning to the XML file. Establishes the remaining LCPUs mapped to their appropriate NUMA nodes
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

## Add emulator pinning to the XML file
func_add_emulator_pinning () {
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain/cputune" --type elem -n "emulatorpin cpuset='`cat $WORKING_DIR/VM_CPU_CORES_EMULATOR`'" -v "" $FILE_LOCATION > $FILE_LOCATION.tmp
}
[ `wc -l $WORKING_DIR/VM_CPU_CORES_EMULATOR | awk '{print$1}'` -gt 0 ] && func_add_emulator_pinning

## Add total number of iothreads to the XML file
## virt-install and virt-xml don't seem to support iothreads
func_add_iothread_number_and_pinning () {
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain" --type elem -n "iothreads" -v "`wc -l $WORKING_DIR/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS | awk '{print$1}'`" $FILE_LOCATION > $FILE_LOCATION.tmp

## Add iothread pinning list to the XML file
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
}
[ `wc -l $WORKING_DIR/VM_CPU_CORES_IOTHREADS | awk '{print$1}'` -gt 0 ] && func_add_iothread_number_and_pinning

################################################
#### Begin virt-xml updates to the XML file ####
################################################

## vcpu placement
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
virt-xml --edit  --vcpu placement="static" < $FILE_LOCATION > $FILE_LOCATION.tmp
## Commented out as it seems like "vcpu cpuset" is ignored if emulatorpin or vcpupin is set
#mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
#virt-xml --edit  --vcpu cpuset="`cat $WORKING_DIR/VM_CPU_REMAINING_COMMA_SEPARATED`" < $FILE_LOCATION > $FILE_LOCATION.tmp
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
virt-xml --edit --vcpu=`wc -l $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS | awk '{print$1}'` < $FILE_LOCATION > $FILE_LOCATION.tmp

## iothreads
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
#virt-xml --add-device iothreads=`wc -l $WORKING_DIR/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS | awk '{print$1}'` < $FILE_LOCATION > $FILE_LOCATION.tmp
#virt-xml --edit --iothreads=`wc -l $WORKING_DIR/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS | awk '{print$1}'` < $FILE_LOCATION > $FILE_LOCATION.tmp

## NUMA node to vCPU mapping
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null

#Creates first and last LCPU per NUMA nodes:
#for EACH in `ls -1 VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS_NUMA_node*`; do NUMA_NODE=`echo $EACH | awk -Fe '{print$2}'`; head -1 $EACH > VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS_FIRST$NUMA_NODE; tail -1 $EACH > VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS_LAST$NUMA_NODE; done

#Creates first and last LCPU per NUMA nodes:
for EACH in `ls -1 $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS_NUMA_node*`
do 
	NUMA_NODE=`echo $EACH | awk -Fe '{print$2}'`
	head -1 $EACH > $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS_FIRST$NUMA_NODE
	tail -1 $EACH > $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS_LAST$NUMA_NODE
done

#Creates first VCPU per NUMA node:
for EACH in `ls -1 $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS_FIRST*`
do 
	FIRST_VCPU_FILE=`echo $EACH | awk -FFIRST '{print$2}'`
	grep "cpuset=\"`cat $EACH`\"" $FILE_LOCATION | awk -F\" '{print$2}' > $WORKING_DIR/FIRST_VCPU_NUMA_NODE$FIRST_VCPU_FILE
done

#Creates last VCPU per NUMA node: 
for EACH in `ls -1 $WORKING_DIR/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS_LAST*`
do 
	LAST_VCPU_FILE=`echo $EACH | awk -FLAST '{print$2}'`
	grep "cpuset=\"`cat $EACH`\"" $FILE_LOCATION | awk -F\" '{print$2}' > $WORKING_DIR/LAST_VCPU_NUMA_NODE$LAST_VCPU_FILE
done

#Establishes KiB memory per NUMA node
NUM_NUMA_NODES=`awk 'END{print NR}' $WORKING_DIR/ALL_NUMA_NODES_UNIQ`; MEMORY_PER_NUMA_NODE=$(echo $(( `cat $WORKING_DIR/MEMORY.var` * 1024 * 1024 / `echo $NUM_NUMA_NODES` )))
for EACH in `cat $WORKING_DIR/ALL_NUMA_NODES_UNIQ`
do 
	FIRST=$(cat $WORKING_DIR/FIRST_VCPU_NUMA_NODE$EACH)
	LAST=$(cat $WORKING_DIR/LAST_VCPU_NUMA_NODE$EACH)
	virt-xml --edit --cpu cell$EACH.id=$EACH,cell$EACH.memory=$MEMORY_PER_NUMA_NODE,cell$EACH.cpus=$FIRST"-"$LAST < $FILE_LOCATION > $FILE_LOCATION.tmp
	mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
done



mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
#cat $FILE_LOCATION
echo ""
echo -e "    ${LBLUE}The final VM XML will be: $FILE_LOCATION${NC}"
echo ""
echo ""

