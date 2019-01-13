#190112 #MA
#!/bin/bash

# INTERVAL_OFFSET=-6171284
function GET_GENESIS_OFFSET() {
    #statements
    GENESIS_HASH=$( $COIN_CLI $COIN_OPTION getblockhash 0 )
    GENESIS_DATA=$( $COIN_CLI $COIN_OPTION getblock $GENESIS_HASH | jq -r '[.time, .difficulty, .previousblockhash] | "\(.[0]) \(.[1]) \(.[2])"' )
    GENESIS_TIME=$( echo $GENESIS_DATA | awk '{print $1}' )
    FIRST_HASH=$( $COIN_CLI $COIN_OPTION getblockhash 1 )
    FIRST_DATA=$( $COIN_CLI $COIN_OPTION getblock $FIRST_HASH | jq -r '[.time, .difficulty, .previousblockhash] | "\(.[0]) \(.[1]) \(.[2])"' )
    FIRST_TIME=$( echo $FIRST_DATA | awk '{print $1}' )
    GENESIS_OFFSET=$(( $FIRST_TIME - $GENESIS_TIME ))
    echo $GENESIS_OFFSET
}

function CONVERT_SCIENTIFIC_NOTATION() {
    # BC to handle scientific notation
    # https://stackoverflow.com/questions/12882611/how-to-get-bc-to-handle-numbers-in-scientific-aka-exponential-notation
    echo ${@} | sed 's#\([+-]\{0,1\}[0-9]*\.\{0,1\}[0-9]\{1,\}\)[eE]+\{0,1\}\(-\{0,1\}\)\([0-9]\{1,\}\)#(\1*10^\2\3)#g' | bc -l
}

# init
POW_LIMIT="1.192074847720173e-07"
COIN_NAME="SugarchainTestnetT5"
POW_NAME="YesPower10Sugar"
DIFF_NAME="DigiShieldN255"
COIN_CLI="$HOME/git/SUGAR/WALLET/sugarchain-v0.16.3/src/sugarchain-cli"

# check COIN_CLI
if [ ! -e $COIN_CLI ]; then
    echo "ERROR: NO COIN_CLI: $COIN_CLI"
    exit 1
fi

COIN_OPTION="-rpcuser=username -rpcpassword=password -testnet"
TOTAL_BLOCK_AMOUNT=$($COIN_CLI $COIN_OPTION getblockcount)
# TOTAL_BLOCK_AMOUNT=300 # test
FILE_NAME="$COIN_NAME-$POW_NAME-$DIFF_NAME.csv"
DIFF_INIT=$(CONVERT_SCIENTIFIC_NOTATION $POW_LIMIT)

# new? or continue?
if [ ! -e $FILE_NAME ]; then
    # echo "NEW: $FILE_NAME"
    echo -e "\e[32mNEW: \t$FILE_NAME\e[39m"
    START_BLOCK=1
    INTERVAL_TOTAL=0
else 
    # echo "CONTINUE: $FILE_NAME"
    echo -e "\e[36mKEEP: \t$FILE_NAME\e[39m"
    START_BLOCK=$(( $( tail -n1 $FILE_NAME | awk '{print $1}' ) + 1 ))
    echo -e "\e[36mCONTINUE FROM $START_BLOCK\e[39m"
    INTERVAL_TOTAL=$(( $( tail -n1 $FILE_NAME | awk '{print $6}' ) + 0 ))
fi 

# make header
printf "\n"
printf "Block / Time / Diff / DiffRatio / Interval / Total / Mean / MA"
printf "\n\n"
sleep 1

# loop
for BLOCK_COUNT in `seq $START_BLOCK $TOTAL_BLOCK_AMOUNT`;
do
    CUR_HASH=$( $COIN_CLI $COIN_OPTION getblockhash $BLOCK_COUNT )
    CUR_DATA=$( $COIN_CLI $COIN_OPTION getblock $CUR_HASH | jq -r '[.time, .difficulty, .previousblockhash] | "\(.[0]) \(.[1]) \(.[2])"' )
    CUR_TIME=$( echo $CUR_DATA | awk '{print $1}' )
    CUR_DIFF=$( echo $CUR_DATA | awk '{print $2}' )
    PRE_HASH=$( echo $CUR_DATA | awk '{print $3}' )
    PRE_DATA=$( $COIN_CLI $COIN_OPTION getblock $PRE_HASH | jq -r '[.time, .difficulty, .previousblockhash] | "\(.[0]) \(.[1]) \(.[2])"') # call RPC twice: it slows 2x
    PRE_TIME=$( echo $PRE_DATA | awk '{print $1}' )
    CUR_DIFF_RATIO=$( echo "scale=3; $(CONVERT_SCIENTIFIC_NOTATION $CUR_DIFF) / $(CONVERT_SCIENTIFIC_NOTATION $POW_LIMIT)" | bc )
    
    if [ $BLOCK_COUNT == 1 ]; then
        CUR_INTERVAL=$(( $CUR_TIME - $PRE_TIME - $(GET_GENESIS_OFFSET) ))
    else
        CUR_INTERVAL=$(( $CUR_TIME - $PRE_TIME ))
    fi
    INTERVAL_TOTAL=$(( $(($INTERVAL_TOTAL + $CUR_INTERVAL)) ))
    INTERVAL_MEAN=$( echo "scale=2; $INTERVAL_TOTAL / $BLOCK_COUNT" | bc )
    
    printf "%s %s %21s %s %2s %s %s\n" $BLOCK_COUNT $CUR_TIME $CUR_DIFF $CUR_DIFF_RATIO $CUR_INTERVAL $INTERVAL_TOTAL $INTERVAL_MEAN | tee -a $FILE_NAME
done

# remove ma file before calculate for clean result
if [ -e $FILE_NAME.MA-255 ]; then
    rm $FILE_NAME.MA-*
fi 

# calculate MA
# https://rosettacode.org/wiki/Averages/Simple_moving_average#AWK
# P = MA_WINDOW
awk '{print $1, $5}' $FILE_NAME | awk 'BEGIN { P = 255; } { x = $2; i = NR % P; MA += (x - Z[i]) / P; Z[i] = x; print $1, MA; }' > $FILE_NAME.MA-255
awk '{print $1, $5}' $FILE_NAME | awk 'BEGIN { P = 85; } { x = $2; i = NR % P; MA += (x - Z[i]) / P; Z[i] = x; print $1, MA; }' > $FILE_NAME.MA-85
awk '{print $1, $5}' $FILE_NAME | awk 'BEGIN { P = 34; } { x = $2; i = NR % P; MA += (x - Z[i]) / P; Z[i] = x; print $1, MA; }' > $FILE_NAME.MA-34

# plot parameters
SET_XRANGE="[0:*]"
SET_YRANGE="[0:10]"
SET_Y2RANGE="[$POW_LIMIT:$POW_LIMIT*2.85]"

# plot draw
gnuplot -persist <<-EOFMarker 
set title "$FILE_NAME"; set term qt size 1200, 600;
set label 1 "LIMIT = $POW_LIMIT"; set label 1 at graph 0.015, 0.94 tc rgb "black";
set label 2 "BLOCKS = $TOTAL_BLOCK_AMOUNT"; set label 2 at graph 0.015, 0.88 tc rgb "black";
set xrange $SET_XRANGE; set xlabel "Block Number"; set xtics 0, 255*1 rotate by 45 right; set xtics add ("N=255" 255);
set yrange $SET_YRANGE; set ylabel "Block Time"; set ytics 0, 1; set ytics nomirror;
set y2range $SET_Y2RANGE; set y2label "Difficulty"; set format y2 '%.3g'; set y2tics $POW_LIMIT, $POW_LIMIT/2.165;
# set grid xtics ytics y2tics mxtics mytics my2tics;
set grid xtics ytics mxtics mytics;
set key invert; # reverse key order
plot \
"$FILE_NAME.MA-34" using 0:2 axis x1y1 w l title "(MA-34) Block Time" lc rgb "#eeeeee" lw 1.0, \
"$FILE_NAME.MA-85" using 0:2 axis x1y1 w l title "(MA-85) Block Time" lc rgb "#cccccc" lw 1.0, \
"$FILE_NAME.MA-255" using 0:2 axis x1y1 w l title "(MA-255) Block Time" lc rgb "black" lw 1.25, \
"$FILE_NAME" using 1:3 axis x1y2 w l title "Difficulty" lc rgb "red" lw 1.25,
# caution at the end: no "\"
EOFMarker
