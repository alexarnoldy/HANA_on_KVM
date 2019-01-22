#!/bin/bash

##### NEED TO TEST FOR XMLLINT AND XMLSTARLET (AKA XML)
## Script to create VM XML file, including vCPU, emulator, IOThread and NUMA node pinnings
RED='\033[0;31m'
LBLUE='\033[1;36m'
NC='\033[0m'

echo -e "    Enter the ${LBLUE}NAME${NC} of the VM:"
read VM_NAME
echo ""
echo ""
echo -e "    Enter the absolute path name to place the output file:"
read PATH_TO_OUTPUT_FILE
FILE_LOCATION=$PATH_TO_OUTPUT_FILE/$VM_NAME.xml
echo ""
echo -e "    ${LBLUE}The final VM XML will be: $FILE_LOCATION${NC}"
echo ""
echo ""

####**** Gather the CPU cores to used 
echo "The CPU cores on this system are:"
lscpu | grep ^"NUMA node"." " | awk -F, '{print$1}'
echo ""

################
## Remove after testing
#START=1
#END=15
################



#################
## Uncomment after testing
echo -e "    Enter the ${LBLUE}FIRST${NC} CPU to be allocated to this VM:"
read START
echo -e "    Enter the ${LBLUE}LAST${NC} CPU to be allocated to this VM:"
read END
#### To be removed: echo "Enter the CPU cores to be used by this VM in the form of start-finish, i.e. 3-8"
#### To be removed: read VM_CPU_CORES_LIST
#################
echo -e "    Enter the amount of ${LBLUE}MEMORY${NC} in MiB to be alloacted to this VM:"
read MEMORY

## Iterate through the cores to find the hyper-thread siblings

cat /dev/null > /tmp/VM_CPU_CORES_ITERATED
while [ $START -le $END ]; do  echo $START >> /tmp/VM_CPU_CORES_ITERATED; START=$(($START+1));done

cat /dev/null > /tmp/VM_CPU_CORES_ITERATED_SIBLINGS
for EACH in `cat /tmp/VM_CPU_CORES_ITERATED`; do cat /sys/devices/system/cpu/cpu$EACH/topology/thread_siblings_list >> /tmp/VM_CPU_CORES_ITERATED_SIBLINGS; done

cat /tmp/VM_CPU_CORES_ITERATED_SIBLINGS | sort -n | uniq > /tmp/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ



echo -e "    How many CPU cores will be used for ${LBLUE}QEMU Emulator threads${NC}?"

read EMULATOR_COUNT

echo ""

echo -e "    How many CPU cores will be used for ${LBLUE}QEMU IOThreads${NC}?"

read IOTHREAD_COUNT


## Establish list of logical CPUs for emulator threads from the beginning of the list of logical CPUs allocated to the VM
cat /dev/null > /tmp/VM_CPU_CORES_EMULATOR
head -`echo $EMULATOR_COUNT` /tmp/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ > /tmp/VM_CPU_CORES_EMULATOR
#tr , '\n' < /tmp/VM_CPU_CORES_EMULATOR > /tmp/VM_CPU_CORES_EMULATOR_SORTED_BY_SIBLINGS

## Process the list of emulator threads, removing the trailing comma
VM_CPU_CORES_EMULATOR=`tr '\n' , < /tmp/VM_CPU_CORES_EMULATOR `
echo "${VM_CPU_CORES_EMULATOR::-1}" > /tmp/VM_CPU_CORES_EMULATOR.tmp
mv /tmp/VM_CPU_CORES_EMULATOR.tmp /tmp/VM_CPU_CORES_EMULATOR

echo ""
#cat /tmp/VM_CPU_CORES_EMULATOR_SORTED_BY_SIBLINGS
echo ""

## Establish list of logical CPUs for iothreads
head -`echo $(( $EMULATOR_COUNT + $IOTHREAD_COUNT ))` /tmp/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ | tail -`echo $IOTHREAD_COUNT` > /tmp/VM_CPU_CORES_IOTHREADS
tr , '\n' < /tmp/VM_CPU_CORES_IOTHREADS > /tmp/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS

echo ""
#cat /tmp/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS
echo ""

## Establish the remaining logical CPUs for the VM
tail -n +`echo $(( $EMULATOR_COUNT + $IOTHREAD_COUNT + 1 ))` /tmp/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ > /tmp/VM_CPU_CORES_REMAINING
tr , '\n' < /tmp/VM_CPU_CORES_REMAINING > /tmp/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS

TOTAL_VCPUS=`wc -l /tmp/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS | awk '{print$1}'`

#cat /tmp/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS

## Iterate through emulator thread list to add the pinning option information for the command
## It appears that pinning emulator threads isn't supported with virt-install
## a possible work around could be running `virsh emulator <domain> <cpu list>`

#echo  "virt-install --name $VM_NAME --memory $MEMORY --vcpu $TOTAL_VCPUS --disk none --pxe --print-xml --dry-run --cputune \\"  > /tmp/VIRT-INSTALL-CMD.sh
#
#COUNTER=1 
#LINES=`wc -l /tmp/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS | awk '{print$1}'` 
#while [  $COUNTER -le $LINES ] 
#do 
#	THIS_LINE=`head  -$COUNTER /tmp/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS | tail -1`
#	printf "vcpupin"$COUNTER".vcpu="$COUNTER",vcpupin"$COUNTER".cpuset="$THIS_LINE',\' >> /tmp/VIRT-INSTALL-CMD.sh
#	echo "" >> /tmp/VIRT-INSTALL-CMD.sh
#	let COUNTER=COUNTER+1
#	LINES=`wc -l /tmp/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS | awk '{print$1}'`
#done


## For some unknown reason, virt-install creates two copies of the output in the output file
## The following line removes duplicates. It should remove the second instance of <domain...> but the actual results remain to be seen
#bash /tmp/VIRT-INSTALL-CMD.sh | xmllint --format --xmlout --recover - 2>/dev/null > $FILE_LOCATION

virt-install --name $VM_NAME --memory $MEMORY --vcpu $TOTAL_VCPUS --disk none --pxe --print-xml --dry-run > $FILE_LOCATION
## The following line removes duplicates. It should remove the second instance of <domain...> and everything inside it, but the actual results remain to be seen
xmllint --format --xmlout --recover $FILE_LOCATION 2>/dev/null >  $FILE_LOCATION.tmp


#### Begin xml (xmlstarlet) updates to the base file created by virt-install
#### Use xml el -v <file> to see all fo the elements, attributes, and values #### 

## Add cputune and numatune elements to the XML file
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain" --type elem -n "cputune" -v "" $FILE_LOCATION > $FILE_LOCATION.tmp 
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain" --type elem -n "numatune" -v "" $FILE_LOCATION > $FILE_LOCATION.tmp 

## Add vCPU pinning to the XML file
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
COUNTER=1 
LINES=`wc -l /tmp/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS | awk '{print$1}'` 
while [  $COUNTER -le $LINES ] 
do 
	THIS_LINE=`head  -$COUNTER /tmp/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS | tail -1`
	xml ed --subnode "/domain/cputune" --type elem -n "vcpupin vcpu='`echo $COUNTER`' cpuset='$THIS_LINE'" $FILE_LOCATION > $FILE_LOCATION.tmp
	mv $FILE_LOCATION.tmp $FILE_LOCATION
	let COUNTER=COUNTER+1
	LINES=`wc -l /tmp/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS | awk '{print$1}'`
done

## Add NUMA node pinning to the XML file
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
numactl --hardware | grep cpus | sed 's/node /node/' > /tmp/NUMA_NODES_TO_CPUS
cat /dev/null > /tmp/ALL_NUMA_NODES
for EACH in `cat /tmp/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS`
do 
	grep -w $EACH /tmp/NUMA_NODES_TO_CPUS | awk -Fe '{print$2}' | awk '{print$1}' >> /tmp/ALL_NUMA_NODES
done
sort /tmp/ALL_NUMA_NODES | uniq > /tmp/ALL_NUMA_NODES_UNIQ

## Process the list of NUMA nodes, removing the trailing comma
ALL_NUMA_NODES_UNIQ=`tr '\n' , < /tmp/ALL_NUMA_NODES_UNIQ `
echo "${ALL_NUMA_NODES_UNIQ::-1}" > /tmp/ALL_NUMA_NODES_COMMA_SEPARATED
xml ed --subnode "/domain/numatune" --type elem -n "memory mode='strict' nodeset='`cat /tmp/ALL_NUMA_NODES_COMMA_SEPARATED`'" $FILE_LOCATION > $FILE_LOCATION.tmp

 

## Isolate the NUMA nodes in to separate files
#COUNTER=1
#LINES=`wc -l /tmp/NUMA_NODES_TO_CPUS | awk '{print$1}'`
#while [  $COUNTER -le $LINES ] 
#do         
#	head  -$COUNTER /tmp/NUMA_NODES_TO_CPUS | tail -1 > /tmp/$COUNTER-NODE
#	let COUNTER=COUNTER+1
#	LINES=`wc -l /tmp/NUMA_NODES_TO_CPUS | awk '{print$1}'`
#done
## Find the NUMA nodes for each LCPU and compile them into a file



## Update hpet timer
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed -u "domain/clock/timer[@name='hpet' and @present='no']"/@present -v yes $FILE_LOCATION > $FILE_LOCATION.tmp

## Add emulatorpinning to the XML file
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
xml ed --subnode "/domain/cputune" --type elem -n "emulatorpin cpuset='`cat /tmp/VM_CPU_CORES_EMULATOR`'" -v "" $FILE_LOCATION > $FILE_LOCATION.tmp

## Add IOThreads to the XML file
mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
COUNTER=1 
LINES=`wc -l /tmp/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS | awk '{print$1}'` 
while [  $COUNTER -le $LINES ] 
do 
	THIS_LINE=`head  -$COUNTER /tmp/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS | tail -1`
	xml ed --subnode "/domain/cputune" --type elem -n "iothreadpin iothread='`echo $COUNTER`' cpuset='$THIS_LINE'" $FILE_LOCATION > $FILE_LOCATION.tmp
	mv $FILE_LOCATION.tmp $FILE_LOCATION
	let COUNTER=COUNTER+1
	LINES=`wc -l /tmp/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS | awk '{print$1}'`
done


mv $FILE_LOCATION.tmp $FILE_LOCATION 2>/dev/null
rm /tmp/VM_CPU_CORES_ITERATED
rm /tmp/VM_CPU_CORES_ITERATED_SIBLINGS 
rm /tmp/VM_CPU_CORES_ITERATED_SIBLINGS_UNIQ
rm /tmp/VM_CPU_CORES_EMULATOR
#rm /tmp/VM_CPU_CORES_EMULATOR_SORTED_BY_SIBLINGS
rm /tmp/VM_CPU_CORES_IOTHREADS
rm /tmp/VM_CPU_CORES_IOTHREADS_SORTED_BY_SIBLINGS
#rm /tmp/VM_CPU_CORES_REMAINING
#rm /tmp/VM_CPU_CORES_REMAINING_SORTED_BY_SIBLINGS

###### virt-install --name test --memory 4096 --vcpu 2 --disk none --pxe --print-xml --dry-run --cputune vcpupin0.vcpu=0,vcpupin0.cpuset=2,vcpupin1.vcpu=1,vcpupin1.cpuset=8
