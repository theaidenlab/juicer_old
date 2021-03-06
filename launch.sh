## Loop over all read1 fastq files and create jobs for aligning read1,
## aligning read2, and merging the two. Keep track of merge names for final 
## merge. When merge jobs successfully finish, can launch final merge job.  
## If any of the jobs fail, the cleanup job will execute and kill the 
## remaining ones.

## Probably in an ideal world, this would be a script that is not concatenated
## but launched on its own with appropriate flags.
countjobs=0
declare -a ARRAY

# these are used to update properties file, and only on MiSeq runs
hicdir=`basename "$topDir"`
newdir="/broad/aidenlab/hic_files/"${hicdir}
newleaf=$(date "+%Y_%m_%d_%H_%M_%S")
#newleaf=$(awk '$1 ~ /leaf0/{split($1,a,"f");if (max < a[2]){max = a[2]}}END{print max+1}' /broad/aidenlab/hic_files/hicInternalMenu.properties)

# Only used for MiSeq files; if no key is given, put under menu item "Latest"
if [ -z "$key" ]; then 
		key="Latest"
fi

for i in ${read1}
do
  ext=${i#*$read1str}
  name=${i%$read1str*}
  # these names have to be right or it'll break
  name1=${name}${read1str}
  name2=${name}${read2str}

  # count ligations
  echo -e '#!/bin/bash -l' > tmp
  echo -e "#BSUB -q $queue" >> tmp
  echo -e "#BSUB -o $topDir/lsf.out\n" >> tmp
  echo -e "#BSUB -g $groupname" >> tmp
  echo -e "num1=\$(paste $name1$ext $name2$ext | grep -c $ligation)" >> tmp
  echo -e "echo -ne \"\$num1 \" > $name${ext}_norm.txt.res.txt" >> tmp
  bsub < tmp

  # align read1 fastq
  echo -e '#!/bin/bash -l' > tmp
  echo -e "#BSUB -q $queue" >> tmp
  echo -e "#BSUB -o $topDir/lsf.out\n" >> tmp
  if [ $shortread ] || [ $shortreadend -eq 1 ]
  then
	  echo -e "#BSUB -R \"rusage[mem=4]\" " >> tmp
	else 
  	echo -e "#BSUB -R \"rusage[mem=6]\" " >> tmp
	fi
  echo -e "#BSUB -g $groupname" >> tmp
  echo -e "#BSUB -J $groupname$name1$ext" >> tmp
  echo -e "source /broad/software/scripts/useuse\nreuse .bwa-0.6.2" >> tmp
  # short read aligner is bwa aln; long read is bwasw.  In the future use only bwa mem.
  if [ $shortread ] || [ $shortreadend -eq 1 ]
  then
    echo "bwa aln $refSeq $name1$ext > $name1$ext.sai" >> tmp
    echo "bwa samse $refSeq $name1$ext.sai $name1$ext > $name1$ext.sam" >> tmp
  else
    echo "bwa bwasw $refSeq $name1$ext > $name1$ext.sam" >> tmp
  fi
  bsub < tmp

  # align read2 fastq
  echo -e '#!/bin/bash -l' > tmp
  echo -e "#BSUB -q $queue" >> tmp
  echo -e "#BSUB -o $topDir/lsf.out\n" >> tmp
  if [ $shortread ] || [ $shortreadend -eq 2 ]
  then
	  echo -e "#BSUB -R \"rusage[mem=4]\" " >> tmp
	else 
  	echo -e "#BSUB -R \"rusage[mem=6]\" " >> tmp
	fi
  echo -e "#BSUB -g $groupname" >> tmp
	if [ ! $splitdirexists ]; then
			echo -e "#BSUB -w \"done(${groupname}move)\"" >> tmp
	fi
  echo -e "#BSUB -J $groupname$name2$ext" >> tmp
  echo -e "source /broad/software/scripts/useuse\nreuse .bwa-0.6.2" >> tmp
  if [ $shortread ] || [ $shortreadend -eq 2 ]
  then
    echo "bwa aln $refSeq $name2$ext > $name2$ext.sai" >> tmp
    echo "bwa samse $refSeq $name2$ext.sai $name2$ext > $name2$ext.sam" >> tmp
  else
    echo "bwa bwasw $refSeq $name2$ext > $name2$ext.sam" >> tmp
  fi
  bsub < tmp

  # wait for top two, merge
  echo -e '#!/bin/bash -l' > tmp
  echo -e "#BSUB -q $queue" >> tmp
  echo -e "#BSUB -o $topDir/lsf.out" >> tmp
  echo -e "#BSUB -R \"rusage[mem=2]\"" >> tmp
  echo -e "#BSUB -g $groupname" >> tmp
  echo -e "#BSUB -w \"done(${groupname}${name1}${ext}) && done(${groupname}${name2}${ext})\"" >> tmp
  echo -e "#BSUB -J ${groupname}merge${name}${ext}\n" >> tmp
  echo -e "source /broad/software/scripts/useuse\nreuse Java-1.7" >> tmp
  echo -e "export LC_ALL=C" >> tmp
  # sort read 1 aligned file by readname 
  echo -e "if ! sort -k1,1 $name1$ext.sam > $name1${ext}_sort.sam" >> tmp
  echo -e "then exit 1; fi" >> tmp
  # sort read 2 aligned file by readname 
  echo -e "if ! sort -k1,1 $name2$ext.sam > $name2${ext}_sort.sam" >> tmp
  echo -e "then exit 1; fi" >> tmp
  # remove header, add read end indicator toreadname
  echo -e "awk 'NF > 5{\$1 = \$1\"/1\";print}' $name1${ext}_sort.sam > $name1${ext}_sort1.sam" >> tmp
  echo -e "awk 'NF > 5{\$1 = \$1\"/2\";print}' $name2${ext}_sort.sam > $name2${ext}_sort1.sam" >> tmp
  # merge the two sorted read end files
  echo -e "sort -k1,1 -m $name1${ext}_sort1.sam $name2${ext}_sort1.sam > $name$ext.sam" >> tmp
  echo -e "rm $name1$ext.sa* $name2$ext.sa* $name1${ext}_sort*.sam $name2${ext}_sort*.sam" >> tmp
  # call chimeric.awk to deal with chimeric reads; sorted file is sorted by read name at this point
  echo -e "awk -v \"fname1\"=$name${ext}_norm.txt -v \"fname2\"=$name${ext}_abnorm.sam -v \"fname3\"=$name${ext}_unmapped.sam -f /broad/aidenlab/neva/neva_scripts/chimeric_blacklist.awk $name$ext.sam" >> tmp
  # if any normal reads were written, find what fragment they correspond to and store that
	echo -e "if [ -e \"$name${ext}_norm.txt\" ]" >> tmp
	echo -e "then " >> tmp 
	echo -e "/broad/aidenlab/neva/neva_scripts/fragment.pl $name${ext}_norm.txt $site_file > $name${ext}.frag.txt" >> tmp
  # sort by chromosome, fragment, strand, and position
	echo -e "sort -k2,2d -k6,6d -k4,4n -k8,8n -k1,1n -k5,5n -k3,3n $name${ext}.frag.txt > $name${ext}.sort.txt" >> tmp
	echo -e "rm $name${ext}_norm.txt $name${ext}.frag.txt" >> tmp
	echo -e "fi" >> tmp	
	bsub < tmp
  rm tmp

  # list of all jobs.  if any fail, i.e., exit(jobid) != 0, we will kill the
  # remaining jobs
  ARRAY[countjobs]="exit(${groupname}${name1}${ext}) || exit(${groupname}${name2}${ext}) || exit(${groupname}merge${name}${ext}) "
  countjobs=$(( $countjobs + 1 ))
done

for (( i=0; i < countjobs; i++ ))
do
# clean up jobs if any fail
  echo -e '#!/bin/bash -l' > tmp
  echo -e "#BSUB -q $queue" >> tmp
  echo -e "#BSUB -o $topDir/lsf.out" >> tmp
  echo -e "#BSUB -w \"${ARRAY[i]}\"" >> tmp
  echo -e "#BSUB -g ${groupname}kill" >> tmp
  echo -e "#BSUB -J cleanup_$groupname$i\n" >> tmp

	echo -e "echo \"/broad/aidenlab/neva/neva_scripts/relaunch_prep.sh \" > $topDir/relaunchme.sh" >> tmp
	echo -e "echo \"/broad/aidenlab/neva/neva_scripts/relaunch.sh $flags\" >> $topDir/relaunchme.sh" >> tmp
  echo -e "bkill -g $groupname 0" >> tmp
  echo -e "bkill -g ${groupname}kill 0" >> tmp
  bsub < tmp
done

# kill the kill jobs if everything went well
echo -e "#!/bin/bash -l" > tmp
echo -e "#BSUB -q $queue" >> tmp
echo -e "#BSUB -o $topDir/lsf.out" >> tmp
echo -e "#BSUB -g $groupname" >> tmp
echo -e "#BSUB -w \"done(${groupname}merge*)\" " >> tmp
echo -e "#BSUB -J ${groupname}_fragmerge1" >> tmp
		
echo -e "bkill -g ${groupname}kill 0\n" >> tmp
bsub < tmp
rm tmp

# merge the sorted files into one giant file that is also sorted.
echo -e "#!/bin/bash -l" > tmp
echo -e "#BSUB -q $queue" >> tmp
echo -e "#BSUB -o $topDir/lsf.out" >> tmp
echo -e "#BSUB -g $groupname" >> tmp
echo -e "#BSUB -w \"done(${groupname}merge*)\" " >> tmp
echo -e "#BSUB -J ${groupname}_fragmerge" >> tmp
		
echo -e	"export LC_ALL=C" >> tmp
echo -e "sort -T /broad/hptmp/neva -m -k2,2d -k6,6d -k4,4n -k8,8n -k1,1n -k5,5n -k3,3n $splitdir/*.sort.txt  > $outputdir/merged_sort.txt" >> tmp 
bsub < tmp

# if it dies, cleanup and write to relaunch script
# note that the relaunch script gets written over so the relaunch script isn't always correct and doesn't work the way I intended.
echo -e "#!/bin/bash -l" > tmp
echo -e "#BSUB -q $queue" >> tmp
echo -e "#BSUB -o $topDir/lsf.out" >> tmp
echo -e "#BSUB -g ${groupname}_clean" >> tmp
echo -e "#BSUB -J ${groupname}_clean1" >> tmp
echo -e "#BSUB -w \"exit(${groupname}_fragmerge)\"" >> tmp
echo -e "echo \"/broad/aidenlab/neva/neva_scripts/relaunch.sh $flags -m\" > $topDir/relaunchme.sh  " >> tmp
echo -e "bkill -g $groupname 0" >> tmp
bsub < tmp
rm tmp
		
# if jobs succeeded, kill the cleanup job, remove the duplicates from the big sorted file
echo -e "#!/bin/bash -l" > tmp
echo -e "#BSUB -q $queue" >> tmp
echo -e "#BSUB -o $topDir/lsf.out" >> tmp
echo -e "#BSUB -g $groupname" >> tmp
echo -e "#BSUB -w \"done(${groupname}_fragmerge*)\" " >> tmp
echo -e "#BSUB -J ${groupname}_osplit" >> tmp
echo -e "bkill -J ${groupname}_clean1" >> tmp
echo -e "awk -v queue=$queue -v outfile=$topDir/lsf.out -v groupname=$groupname -v dir=$outputdir -f /broad/aidenlab/neva/neva_scripts/split_rmdups.awk $outputdir/merged_sort.txt" >> tmp
		
bsub < tmp
rm tmp

# if it dies, cleanup and write to relaunch script
echo -e "#!/bin/bash -l" > tmp
echo -e "#BSUB -q $queue" >> tmp
echo -e "#BSUB -o $topDir/lsf.out" >> tmp
echo -e "#BSUB -g ${groupname}_clean" >> tmp
echo -e "#BSUB -J ${groupname}_clean2" >> tmp
echo -e "#BSUB -w \"exit(${groupname}_osplit)\"" >> tmp
echo -e "echo \"/broad/aidenlab/neva/neva_scripts/relaunch.sh $flags -m \" > $topDir/relaunchme.sh  " >> tmp
echo -e "bkill -g $groupname 0" >> tmp
echo -e "bkill -g ${groupname}_clean 0" >> tmp
bsub < tmp
rm tmp

# if early exit, we stop here, once the merged_nodups.txt file is created.
if [ -z "$earlyexit" ]
    then
		echo -e "#!/bin/bash -l" > tmp
		echo -e "#BSUB -q $queue" >> tmp
		echo -e "#BSUB -o $topDir/lsf.out" >> tmp
		echo -e "#BSUB -g $groupname" >> tmp
		echo -e "#BSUB -w \"done(${groupname}_osplit)\" " >> tmp
		echo -e "#BSUB -J ${groupname}launch" >> tmp		
		echo -e "echo Splits done, launching other jobs." >> tmp
		echo -e "bkill -J ${groupname}_clean2" >> tmp
		echo "bsub -o $topDir/lsf.out -q $queue -g ${groupname}_clean -w \"done(${groupname}_kill)\" \"echo /broad/aidenlab/neva/neva_scripts/relaunch_dups.sh $flags > $topDir/relaunchme.sh\" " >> tmp
		echo "bsub -o $topDir/lsf.out -q $queue -g $groupname -w \"done(${groupname}_split)\" -J ${groupname}stats \"source /broad/software/scripts/useuse; reuse Java-1.7; /broad/aidenlab/neva/neva_scripts/statistics.pl -s $site_file -l $ligation -o $outputdir/stats_dups.txt $outputdir/dups.txt; export LC_ALL=en_US.UTF-8; echo 'Experiment description: $about' > $outputdir/inter.txt; cat $splitdir/*.res.txt | awk -f /broad/aidenlab/neva/neva_scripts/stats_sub.awk >> $outputdir/inter.txt; java -cp /broad/aidenlab/neva/neva_scripts/ LibraryComplexity $outputdir inter.txt >> $outputdir/inter.txt; /broad/aidenlab/neva/neva_scripts/statistics.pl -s $site_file -l $ligation -o $outputdir/inter.txt -q 1 $outputdir/merged_nodups.txt; cat $splitdir/*_abnorm.sam > $outputdir/abnormal.sam; cat $splitdir/*_unmapped.sam > $outputdir/unmapped.sam; awk -f /broad/aidenlab/neva/neva_scripts/abnormal.awk $outputdir/abnormal.sam > $outputdir/abnormal.txt\" " >> tmp
		echo -e "bsub -o $topDir/lsf.out  -q $queue -R \"rusage[mem=4]\" -g $groupname -w  \"done(${groupname}stats)\" -J ${groupname}hic \" source /broad/software/scripts/useuse; reuse Java-1.7; /broad/aidenlab/juicebox pre -f $site_file -s $outputdir/inter.txt -g $outputdir/inter_hists.m -q 1 $outputdir/merged_nodups.txt $outputdir/inter.hic $genomeID ; if [[ $topDir == *MiSeq* ]]; then mkdir $newdir; ln -s $outputdir/inter*.hic $newdir/. ; echo leaf${newleaf} = ${key}, ${hicdir} ${about} \(\\\$(awk '{sum+=\\\$1}END{print sum}' $splitdir/*.res.txt)\), https://iwww.broadinstitute.org/igvdata/hic/files/${hicdir}/inter.hic >> /broad/aidenlab/hic_files/hicInternalMenu.properties;  fi  \" " >> tmp
		echo -e "bsub -o $topDir/lsf.out  -q $queue -R \"rusage[mem=4]\" -g $groupname -w  \"done(${groupname}_split)\" -J ${groupname}hic30 \"source /broad/software/scripts/useuse; reuse Java-1.7; export LC_ALL=en_US.UTF-8; echo 'Experiment description: $about' > $outputdir/inter_30.txt; cat $splitdir/*.res.txt | awk -f /broad/aidenlab/neva/neva_scripts/stats_sub.awk >> $outputdir/inter_30.txt; java -cp /broad/aidenlab/neva/neva_scripts/ LibraryComplexity $outputdir inter_30.txt >> $outputdir/inter_30.txt;   /broad/aidenlab/neva/neva_scripts/statistics.pl -s $site_file -l $ligation -o $outputdir/inter_30.txt -q 30 $outputdir/merged_nodups.txt; /broad/aidenlab/juicebox pre -f $site_file -s $outputdir/inter_30.txt -g $outputdir/inter_30_hists.m -q 30 $outputdir/merged_nodups.txt $outputdir/inter_30.hic $genomeID \" " >> tmp 
		bsub < tmp
		rm tmp

		echo -e "#!/bin/bash -l" > tmp
		echo -e "#BSUB -q $queue" >> tmp
		echo -e "#BSUB -o $topDir/lsf.out" >> tmp
		echo -e "#BSUB -g ${groupname}_clean" >> tmp
		echo -e "#BSUB -w \"done(${groupname}launch)\"" >> tmp
		echo -e "bsub -o $topDir/lsf.out -q $queue -g ${groupname}_clean -w \"exit(${groupname}stats) || exit(${groupname}hic) || exit(${groupname}hic30)\" \"echo /broad/aidenlab/neva/neva_scripts/relaunch.sh $flags -f > $topDir/relaunchme.sh; bkill -g $groupname 0; bkill -g ${groupname}_clean 0 \" " >> tmp
		bsub < tmp
		rm tmp

		echo -e "#!/bin/bash -l" > tmp
		echo -e "#BSUB -q $queue" >> tmp
		echo -e "#BSUB -o $topDir/lsf.out" >> tmp
		echo -e "#BSUB -g ${groupname}_clean" >> tmp
		echo -e "#BSUB -J ${groupname}_clean3" >> tmp
		echo -e "#BSUB -w \"done(${groupname}launch)\"" >> tmp
		echo -e "bsub -o $topDir/lsf.out -q $queue -g ${groupname} -w \"done(${groupname}stats) && done(${groupname}hic) && done(${groupname}hic30)\" \"bkill -g ${groupname}_clean 0; echo 'Pipeline successfully completed'\" " >> tmp
		bsub < tmp
		rm tmp
fi
