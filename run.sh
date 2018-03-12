#!/bin/bash

## This is a simple script with rudimentary checks and balances designed to automate the running of tests in topologies with the right model checker and arguments, saving the output and producing a summary based on the expected result for each. Importantly, our models are version controlled; the outputs and summary saved by this script are marked with the current model's version. In this way, historical models can be correlated with their results.

TOPOLOGY_FILES=`ls | grep -E '^topology[[:digit:]]'`

# if this script has been run specifying a particular topology to be checked
if [[ $1 ]]; then

	# check only that topology
	TOPOLOGY_LIST=`echo "$TOPOLOGY_FILES" | grep "$1"`

else

	# otherwise, check all topologies
	TOPOLOGY_LIST=$TOPOLOGY_FILES

fi

# check there are no duplicate named tests in any of the topologies
DUPLICATE_TESTS=`grep -v ^% $TOPOLOGY_LIST | awk '/THEOREM/{print $1}' | grep -E 'group[[:digit:]]+_test[[:digit:]]+' | awk -F '_' '{print $1"_"$2}' | sort | uniq -d | wc -l`
if [[ $DUPLICATE_TESTS -ne 0 ]]; then

	# return error
	echo "Error: topologies contain duplicate named tests"
	exit 1

fi

# the working topology file
RUN_TOPOLOGY="topology.sal"

# current model version
GIT_COMMIT=`git rev-parse HEAD`

# GIT_STATUS will be 0 if the model has not been changed since last git commit and 1 otherwise. This is important, as results are saved with this marker to indicate whether they reflect the results of the last committed version, or a subsequently modified version.
GIT_STATUS=`git status | grep -c 'Changes not staged for commit'`

# where the summary (pass or fail) for all tests will be saved
SUMMARY_FILE="./Data/summary-$GIT_COMMIT-$GIT_STATUS"

# remove the old summary file, should it exist from a previous run of this script with the same commit level
rm -f $SUMMARY_FILE

for topology_file in $TOPOLOGY_LIST
do

	# SAL expects topology.sal, so we need to copy it there
	cat $topology_file > $RUN_TOPOLOGY

	# check the topology file's syntax
	TOPOLOGY_SYNTAX=`sal-wfc $RUN_TOPOLOGY`

	# if the topology doesn't have syntax errors
	if [[ `echo "$TOPOLOGY_SYNTAX" | grep -c Ok` -eq 1 ]]; then

		topology_name=`echo $topology_file | sed 's/.sal$//'`

		# generate a list of tests to run (which aren't commented out nor have an invalid name)
		PREDICATE_LIST=`grep -v ^% $RUN_TOPOLOGY | awk '/THEOREM/{print $1}' | grep -E 'group[[:digit:]]+_test[[:digit:]]+_[[:digit:]]+_(true|false)'`

		for predicate_name in $PREDICATE_LIST
		do

			# depth used to determine which model checker for test
			DEPTH=`echo $predicate_name | awk -F '_' '{print $3}'`

			OUTPUT_FILE="./Data/$topology_name-$predicate_name-$GIT_COMMIT-$GIT_STATUS.output"
			# remove an old output file if it exists
			rm -f $OUTPUT_FILE

			# determine whether or not test should produce a counter-example
			# N.B. true means predicate holds; false does not (ie. counter-example)
			EXPECTED_RESULT=`echo $predicate_name | awk -F '_' '{print $4}'`

			# if the model should be checked to its full depth
			if [[ $DEPTH -eq 0 ]]; then

				# run test without depth limit
				sal-smc -v 3 topology $predicate_name > $OUTPUT_FILE 2>&1

				# save return code
				RETURNED=$?
				
				# determine if test produced counter-example
				RESULT=`grep -c proved. $OUTPUT_FILE`

				# determine depth if counter-example found
				COUNTER_EXAMPLE=$((`egrep 'Step [[:digit:]]' $OUTPUT_FILE | wc -l` - 1))
		
				# if the result of the test was as expected
				if [[ $RETURNED -eq 0 && ((("$EXPECTED_RESULT" == "true") && ($RESULT -eq 1)) || (("$EXPECTED_RESULT" == "false") && ($RESULT -eq 0))) ]]; then

					echo "$topology_name-$predicate_name passed $COUNTER_EXAMPLE" | tee -a $SUMMARY_FILE

				else

					echo "$topology_name-$predicate_name failed $COUNTER_EXAMPLE" | tee -a $SUMMARY_FILE

				fi

			else

				# run test with depth limit
				sal-bmc -v 3 --depth=$DEPTH topology $predicate_name > $OUTPUT_FILE 2>&1

				# save return code
                                RETURNED=$?

				# determine if test produced counter-example
				RESULT=`grep -c 'no counterexample between depths' $OUTPUT_FILE`

				# determine depth if counter-example found
				COUNTER_EXAMPLE=$((`egrep 'Step [[:digit:]]' $OUTPUT_FILE | wc -l` - 1))

				# if the result of the test was as expected
				if [[ $RETURNED -eq 0 && ((("$EXPECTED_RESULT" == "true") && ($RESULT -eq 1)) || (("$EXPECTED_RESULT" == "false") && ($RESULT -eq 0))) ]]; then

                                	echo "$topology_name-$predicate_name passed $COUNTER_EXAMPLE" | tee -a $SUMMARY_FILE

                        	else

                                	echo "$topology_name-$predicate_name failed $COUNTER_EXAMPLE" | tee -a $SUMMARY_FILE

                        	fi

			fi

		done
	
	else

		# syntax of topology is invaild; save error to summary file
		echo "$TOPOLOGY_SYNTAX" | tee -a $SUMMARY_FILE

	fi

done

# remove working topology file
rm -f topology.sal
