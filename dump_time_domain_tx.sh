#!/bin/bash
# Copyright 2022-2025 NXP
#
# NXP Confidential. This software is owned or controlled by NXP and may only
# be used strictly in accordance with the applicable license terms. By expressly accepting
# such terms or by downloading, installing, activating and/or otherwise using
# the software, you are agreeing that you have read, and that you agree to
# comply with and are bound by, such license terms. If you do not agree to
# be bound by the applicable license terms, then you may not retain,
# install, activate or otherwise use the software.


print_usage()
{
echo
echo "usage ./dump_time_domain_tx.sh [ant_id] [dpdo] [num_32K] [0.5ms|1ms|2ms|5ms|10ms|20ms|40ms] [HRAM|H2M|DDR] [mem] [obs|obs4|obs5] [offset=x]"
echo "	ant_id:       0-5 representing the 6 DCS channels"
echo "	dpdo:         dump DPD output 20/40ms,  if dpdi or dpdo is not specified, dump 20/40ms TX ant data sent to AXIQ/DAC."
echo "	num_32K:      dump size, number of 32KB. 1=32KB, 2=64KB etc, if not specified, dump size will be decided by dump_time_len"
echo "  0.5ms|1ms|2ms|5ms|10ms|20ms|40ms: dump time length"
echo "	HRAM|H2M|DDR:     use HRAM(HRAM 6MB) H2M(HRAM 2MB) or DDR memory as dump memory"
echo "	mem:          dump to memory without saving to file from memory"
echo "	offset=x:     offset from boundary, x=1-0x7F, num of 64KB. For example offset=5 will set the dump to start from offset 320KB after the boundary"
echo "	obs|obs4|obs5:synchronously dump of DPD observation channel when dpdo is set, obs:observation channel is same as RX channel, obs4/5: using HSADC0/1 as obs channel,"
echo "	example: ./dump_time_domain_tx.sh   		will dump 20/40ms TX ant data before AXIQ for antenna 0"
echo "	example: ./dump_time_domain_tx.sh 1  		will dump 20/40ms TX ant data before AXIQ for antenna 1"
echo "	example: ./dump_time_domain_tx.sh 0 dpdo  	will dump 20/40ms DPD output data for antenna 0"
echo "	example: ./dump_time_domain_tx.sh 1 dpdi  	will dump 20/40ms DPD input data for antenna 1" 
echo "	example: ./dump_time_domain_tx.sh 0 dpdo 2	will dump 64KB DPD output data for antenna 0"
echo
}

#To retrieve the dump filename, use the following way:
#log=$(./dump_time_domain_tx.sh [arg])                       #run the command, log info will be saved to $log
#echo "$log"                                                 #print the log is needed.
#filename=`echo "$out" | grep file: | cut -d ":" -f3`        #retrieve the filename from log.

print_tx_dump_check_correct()
{
echo
echo "***** CORRECT! CORRECT! CORRECT! ***** Ant data sent to DAC are expected."
echo
}

source ./check_dfe_cap_core_map.sh

known_waveform_list=(
408e1cf64094b35101316f708bce52e8 "TM3.3_50MHz_30kHz_FDD 245Msps time domain 20ms dump"
1f977eae9bb5f8c6d0effc1e21ffe392 "TM3.3_50MHz_30kHz_FDD 245Msps time domain 20ms dump with auto scaling"
08d1129c11c6daae6d3102ef06c4b52a "TM3.3_25MHz_30kHz_FDD 122Msps time domain 20ms dump"
f893c91332db0df79621acfea2f991a8 "TM3.3_5MHz_15kHz_TDD 61Msps time domain 20ms dump for pattern DDGGG GGUUG GGGGG UUUUG"
4cd4cd46bdc9264cca21fa86277b9d9a "TM3.3_5MHz_15kHz_FDD 61Msps time domain 20ms dump"
4ebb9f1c03e64ae3f850f16e57fcf450 "TM3.3_20MHz_30kHz_FDD 61Msps time domain 20ms dump"
b34df33f4cc09341a84ccd7c847994bf "TM3.3_20MHz_30kHz_FDD 61Msps time domain 20ms dump with filter delay compensation"
0d2be5275a9e9a974c8c562fa2b162bf "TM3.3_20MHz_60kHz_FDD 61Msps time domain 20ms dump"
022a314fe2359f6e543f8afdee2d152c "TM3.3_10MHz_30kHz_FDD 61Msps time domain 20ms dump"
c6b30a1f4144c6f9ea722d3bace353df "TM3.3_10MHz_30kHz_FDD 61Msps time domain 20ms dump auto scaled"
682615e16cbeb542d4b08a032b7e041a "TM3.3_20MHz_30kHz_FDD 122Msps time domain 20ms dump"
6f260503977d51f9ab450d1857eebd2c "TM3.3_20MHz_30kHz_FDD 61Msps LA12xx time domain 20ms dump"
527c4c00f041dddf1e1fea804b0b4df7 "TM3.3_20MHz_30kHz_FDD 61Msps time domain scaled 125% 20ms dump"
33388ed91bc0d08b7b14fa9dbb891ab0 "TM3.3_20MHz_30kHz_FDD 61Msps time domain with phase compensation 20ms dump"
8fe56bc403590ba78d70ce4d21f132e3 "TM3.3_20MHz_30kHz_FDD 61Msps time domain with fine CFO 30Khz 20ms dump"
60db8d423523ff27ea46d6c8777ab7b7 "TM3.3_20MHz_30kHz_FDD 61Msps time domain 20ms dump QEC 0 taps imb applied"
9016a4d86966bdffce953af8f2f00e42 "TM3.3_20MHz_30kHz_FDD 61Msps time domain 20ms dump QEC 0 taps imb+dc applied"
1efe967737c46f09fc1b15671f1aa262 "TM3.3_20MHz_30kHz_FDD 61Msps time domain 20ms dump with timing offset 1 sample"
817da4f0228ce0fe0c05d18d3e08b3a3 "G-FR1-A1-5_20MHz_30kHz_TDD (3 6 1 4 0 0   2 10 2 2 0 0) option8 61Msps time domain 20ms dump"
35cdaad11c9ca2c6e35841b172404eb5 "G-FR1-A1-5_20MHz_30kHz_TDD (0 6 0 6 0 0) 61Msps time domain 20ms dump"
126afee25c3a4a7311094c9b802c0131 "G-FR1-A1-5_20MHz_30kHz_TDD (3 6 1 4 0 0   2 10 2 2 0 0) 61Msps time domain 20ms dump"
de48af0f6cd8947ef36f25731d146800 "G-FR1-A1-5_20MHz_30kHz_TDD (3 6 1 4 0 0   2 10 2 2 0 0) 61Msps time domain 20ms DCSFDD dump"
1444cd9c056670bd8bb4a0978f7668bf "G-FR1-A1-5_20MHz_30kHz_TDD (3 6 1 4 0 0   2 10 2 2 0 0) 61Msps time domain with phase compensation 20ms dump"
dc646dbc1dda3a137273b520a6e0ffb4 "G-FR1-A1-5_20MHz_30kHz_TDD (3 6 1 4 0 0   2 10 2 2 0 0) 61Msps time domain with CFO 30Khz 20ms dump"
c794c2d049993a5e4eecd0f80cccfe64 "G-FR1-A1-5_20MHz_30kHz_TDD (3 6 1 4 0 0   2 10 2 2 0 0) 61Msps time domain with CFO 30Khz 20ms dump CFO QEC integrated"
331563c1ad6e5d98cb5c1bf6a0377c3c "TDD 20MHz_30kHz (3 6 1 4 0 0   2 10 2 2 0 0) 61Msps time domain single subcarrier 20ms dump"
d7b2e14bd25aa8f0071e8d208f570b4e "TDD 20MHz_30kHz+60Khz (3 6 1 4 0 0   2 10 2 2 0 0) 61Msps time domain two subcarriers 20ms dump"
d629f0fc7d631697b8dc687ab895e2d3 "G-FR1-A1-5_20MHz_30kHz_TDD (3 6 1 4 0 0   2 10 2 2 0 0) 61Msps time domain with QEC imb 20ms dump"
e23f3d45f799caccf7aa241d6e695fc4 "G-FR1-A1-5_20MHz_30kHz_TDD (3 6 1 4 0 0   2 10 2 2 0 0) 61Msps time domain with QEC imb+dc 20ms dump"
2c3ca906accc70ba1ba9650908320a49 "G-FR1-A1-5_20MHz_30kHz_TDD (3 6 1 4 0 0   2 10 2 2 0 0) 61Msps time domain with 125% scaling 20ms dump"
bb22e83c05a898285138276bf79c3387 "TDD (3 6 1 4 0 0   2 10 2 2 0 0) 61Msps single tone 30Khz time domain 20ms dump"
c21ee401e704d9c0002b0da4f727ee81 "TM3.3_5MHz_15kHz_FDD 61Msps option8 time domain 20ms dump"
3902e2b4938859f9fd301862f19f8554 "counter in TX sym buffer option8 4xup disabled time domain 20ms dump"
a7ec2280fe1f364c90f0b5a52ca6430a "TM3.3_10MHz_15kHz_FDD 61Msps time domain 20ms dump"
371ff2eb421186cf62160a5b48151320 "TM3.3_10MHz_15kHz_TDD 61Msps time domain 20ms dump for pattern DDGUG"
ac6ff4abe86e5b9c796e9ee57631ec78 "TM3.3_10MHz_15kHz_TDD 61Msps time domain 20ms dump for pattern DDGGG GGUUG GGGGG UUUUG"
bccbdab7f62763014a6d2026ee99ef44 "FDD single tone 15Khz 25% scale at 61Msps time domain dump" 
3186a4b1fcc7cc4375f90a788fb71b48 "FDD single tone 30Khz 25% scale at 61Msps time domain dump" 
3ab0d88793f8dec448f873138ac0b536 "FDD single tone 30Khz+10Mhz 25% scale at 61Msps time domain dump" 
3bb1c08daf9c65b4481146c241619857 "FDD single sub-carrier 30Khz 0x3FFF3FFF at 61Msps time domain dump" 
1111718e0199202abb441bfe0789500f "FDD two sub-carrier 30Khz 0x3FFF3FFF at 61Msps time domain dump"  
46fe8a6b37670ede0d74bac0052f5bc0 "TDD single tone 15Khz 25% scale at 61Msps time domain dump for pattern DDGGG GGUUG GGGGG UUUUG"
2a424de0edfbc25f23b2ad91f24ffe5b "TDD single tone 15Khz 25% scale at 61Msps time domain dump for pattern DDGUG"
9f7435569dbc2ac4d1ba1dc9e35689d7 "TM1.1 TX timedomain 4x TDD new waveform(491Msps) 20ms dump"
d710f56c37e35ae3ca62237d4dfb5852 "TM1.1 TX timedomain 4x FDD new waveform(491Msps) DPD output 6MB RD1 HP passthrough"
ce79e96a539a98dc18532d5476c35b53 "TM1.1 TX timedomain 4x FDD new waveform(491Msps) DPD output 6MB RD1 HP coeff applied"
61f21bead949b6b33ab1c058a6e0e63f "TM1.1 TX timedomain 4x FDD new waveform(491Msps) 20 dump RD1 HP coeff applied"
f1243190b4aad9cd5643f2a95d41ebc7 "TM1.1 TX timedomain 4x FDD new waveform(491Msps) DPD output 6MB RD1 LP coeff applied"
ab4d27bf5eb04a07be197d2670bece56 "TM1.1 TX timedomain 4x FDD new waveform(491Msps) 20 dump RD1 LP coeff applied"
30fa5e41b9b2a0d3f1d96b899badf798 "TM1.1 TX timedomain 4x FDD new waveform(491Msps) 20 dump RD1 LP coeff applied"
2d656b81de4bb3596ec1fe395ea14225 "TM1.1 TX timedomain 4x FDD new waveform(491Msps) 20 dump RD1 LP coeff applied (open loop)"
3fbbba660fe1028a8fc12900805ad814 "TM1.1 TX timedomain 491Msps waveform 20ms input 20ms dump"
87dc256870c6f3750e478c4e916610d6 "TM1.1 TX timedomain 4x waveform(491Msps) 10ms input 20ms dump"
6547cbae9efd5cee378f2ad9d6114bf8 "TM1.1 TX timedomain 4x FDD new waveform(491Msps) 10ms input 20ms dump QEC passthrough"
c9b35ebde5f5f046f9e12a164cf1e9ed "TM1.1 TX timedomain 4x FDD new waveform(491Msps) 10ms input 20ms dump QEC passthrough DPD model 01 coeff applied"
7fcb68855535f9585c73096a9f99847f "TM1.1 TX timedomain 4x FDD new waveform(491Msps) 10ms input 20ms dump QEC passthrough DPD model 522 coeff applied"
5a6d9b9126748b223b86a35bd487b95b "TM1.1 TX timedomain 4x FDD new waveform(491Msps) 10ms input 20ms dump QEC passthrough DPD model 02 coeff applied"
faa6be778db04a3559843a561bafed2d "TM1.1 TX timedomain 4x FDD new waveform(491Msps) 10ms input 20ms dump QEC passthrough DPD model RD2 coeff applied"
c86db4a67ed59b3de19a241ff193d3d9 "TM1.1 TX timedomain 4x FDD new waveform(491Msps) 10ms input 20ms dump QEC taps 0 applied"
5b52e587fe6959590fbd1352e7acbae9 "TM1.1 TX timedomain 4x FDD new waveform(491Msps) 6MB dump"
6588d093d58017be885ef94776a8bdd8 "TM1.1 TX timedomain 4x new ori waveform(491Msps) 10ms input 20ms dump"
52a47a7596ebccf1fd9f6004c42fa883 "TM1.1 TX timedomain 491Msps waveform, DPD coeff file dpd_coeff_MDPD_fp32.flp"
6d3095779ab58c778d13a812e1e8981c "TM1.1 TX timedomain 4xupsampling 64taps 491Msps waveform 20ms input 20ms dump" 
ec773ef3b3d0368a11a20215af5bbcd6 "TM1.1 TX timedomain 4xupsampling 64taps 491Msps waveform 10ms input 20ms dump" 
dce559c919d324918dc79f6eebb01b28 "TM1.1 TX timedomain 4xupsampling new 64taps(75db) 491Msps waveform 10ms input 20ms dump" 
931a80c4123a99635ea46732ff108c0b "TM1.1 TX timedomain 4xupsampling new 64taps(82db) 491Msps waveform 10ms input 20ms dump" 
3b0c7347d667667857adf3b9237759c3 "TM1.1 TX timedomain FDD 491Msps waveform 10ms input 20ms dump" 
39b3bb639e337fc6020f5d4e99f34021 "TM1.1 TX timedomain FDD 491Msps waveform 20ms dump with phase comopensation" 
312751f0ff334a0cf673677387db31d7 "TM1.1 TX timedomain TDD 491Msps waveform 20ms dump with phase comopensation" 
6e0e17c66b0df8c0e1aa1c7347863f14 "TM1.1 TX timedomain FDD 491Msps waveform with FINE CFO 30Khz 20ms dump" 
c918b11dcbe9ab0c6b3c375f87b9e4b5 "TM1.1 TX timedomain TDD 491Msps waveform with FINE CFO 30Khz 20ms dump" 
c34e3efb4f1b2fb994a52e5a35b220ad "TM1.1 TX timedomain FDD 491Msps waveform 10ms input 20ms dump with 125% scaling" 
0f4c37af7319d93521784f006f7622ea "TM1.1 TX timedomain FDD 491Msps waveform 10ms input 20ms dump CFR enabled" 
9e17ebeb982eb6531cd201b7031bbbde "TM1.1 TX timedomain FDD 491Msps waveform 10ms input 6MB dump" 
65b47d91b8683410f855a794eaf77fa5 "TM1.1 TX timedomain 4xupsampling new 64taps(stop1000) 491Msps waveform QEC tap 0 applied" 
0447ae3b9753efe777cb9f5940d82cad "TM1.1 TX timedomain 4xupsampling new 64taps(stop1000) 491Msps waveform QEC tap 0 with DC offset -0.125:0.125 applied"
132543d9f569f4abdc75aaead785267a "TM1.1 TX timedomain FDD 20Mhz 4xupsampling new 64taps(stop1000) 491Msps waveform CFO QEC integrated kernel QEC tap 0 with DC offset -0.125:0.125 applied"
7981af48c309d3679ba3e38b54debe39 "TM1.1 TX timedomain TDD 20Mhz 4xupsampling new 64taps(stop1000) 491Msps waveform CFO QEC integrated kernel QEC tap 0 with DC offset -0.125:0.125 applied"
5ff08266e33e9d202fb0681838353432 "TM1.1 TX timedomain 4xupsampling new 64taps(stop1000) 491Msps waveform DPDO 32KB (Freq domain input waveform)" 
dbffa73607b3dd9d8eefec30ace3cc34 "TM1.1 TX timedomain 4xupsampling 64taps TDD 20ms dump" 

#list for TX Timedomain ant dump:
51a78e1cdf899131a7b61ce0ba8bab52 "Default TM3.3 50Mhz 15Khz TDD waveform." 
6cc35b9485f66ebfd83f5eda2eca54dc "Default TM3.3 50Mhz 15Khz TDD Freq domain waveform." 
45f933f6fcf6e2c0f462e9e206aecd29 "Default TM3.3 50Mhz 15Khz TDD Freq domain waveform RX dump." 
7814c706a8b7aa2e244075cd48755b8b "Default TM3.3 50Mhz 15Khz TDD Time domain waveform 61Msps." 
71e2806db345b010a3000d0f420dad74 "Default TM3.3 50Mhz 15Khz TDD Time domain waveform 61Msps." 
c5d6b6d04088bb5de9627a2bda6a97ba "Default TM3.3 50Mhz 15Khz TDD run as FDD waveform." 
8086a7b92c5e4413ee37942668544dea "Default TM3.3 50Mhz 15Khz TDD run as FDD 8x up-sampling waveform." 
266d7b579d1fea659201def1327e52eb "Default TM3.3 100Mhz 30Khz TDD waveform." 
55a0185d4f5c6627b3d3442b4156404a "Default TM3.3 100Mhz 30Khz TDD waveform used in FDD." 
ff2701a9992e8d9a70aa49ac76ee0375 "Default TM3.3 100Mhz 30Khz TDD waveform IDC." 
70cb9672455cb7a6e4d38086316c4dd7 "Default TM3.3 100Mhz 30Khz TDD 9-bit compressed waveform." 
00e9eb3751515261e05926763841797d "Default TM3.3 100Mhz 30Khz TDD 4x32 taps upsampling waveform IDC." 
1f93698b0172fdbc804322c5f0db5e00 "Default TM3.3 100Mhz 30Khz TDD 4x32 taps upsampling waveform." 
b2ce2bab64c6f97135b72b4953447686 "Default TM3.3 100Mhz 30Khz TDD 4x64 taps half precision upsampling waveform." 
e5f42a19b8705dcbf09c1d46245c4129 "Default TM3.3 100Mhz 30Khz FDD 4x64 taps single precision upsampling waveform." 
241131520ea4873acf80f99e6db15a80 "Default TM3.3 100Mhz 30Khz TDD 4x64 taps single precision upsampling waveform." 
19c1f2e93040a5c34041d1fe97805e14 "Default TM3.3 100Mhz 30Khz TDD 4x64 taps(stop10000) single precision upsampling waveform." 
58d5b09eb81e5e380e24ea9bbdef64bd "Default TM1.1 100Mhz 30Khz TDD 491Msps TX 20ms dump waveform" 
a22f3781c3897014418a43ab178688fe "Default TM1.1 100Mhz 30Khz TDD 491Msps TX 20ms dump waveform with 125% scaling" 
e4716a268aa168085f38d9907d9179f4 "Default TM1.1 100Mhz 30Khz TDD 491Msps TX 20ms dump waveform CFR enabled." 
a67cd85d4ceb5cca7573c3a87cdc8677 "Default TM1.1 100Mhz 30Khz TDD 491Msps TX 20ms dump waveform 6MB QEC passthrough." 
be418fa8893a5b880f4b509a8e7bfd7c "Default TM1.1 100Mhz 30Khz TDD 491Msps TX 20ms dump waveform QEC tap 0 applied." 
6496d219bcfd7eed1fc55b8e2357695b "Default TM1.1 100Mhz 30Khz TDD 491Msps TX 20ms dump waveform QEC tap 0 with DC offset -0.125:0.125 applied." 
183f760e08268107ceae18cdb44fe91a "Default TM1.1 100Mhz 30Khz FDD 491Msps TX 20ms dump waveform QEC tap 0 with DC offset -0.125:0.125 applied." 
8ff5c5cf89bb4c176bddde304053e4af "Default TM3.3 100Mhz 30Khz TDD 2x16+2x16 taps upsampling waveform." 
31a3070f0b05453a5de790cf005599d6 "Default TM3.3 100Mhz 30Khz TDD CFR All 3 PASS enabled waveform"
e41a6817ee5d025f08a4032b34c7a97a "Default TM3.3 100Mhz 30Khz TDD QEC coeff updated waveform." 
ce6ad6464445ae652e4a39e655212bac "Default TM3.3 100Mhz 30Khz TDD QEC coeff updated with filter bypassed waveform." 
b686fc6c5a457869885922ea5c9db2a9 "Default TM3.3 100Mhz 30Khz TDD CFR All 3 PASS enabled DPD output waveform"
9c136777cb80f6aab0fe7b0a6a3d2039 "Default TM3.3 100Mhz 30Khz TDD CFR disabled timedomain 245Msps waveform."
8e45e570fafab968185349126f44f7a3 "Default TM3.3 100Mhz 30Khz FDD timedomain 245Msps waveform 2x 32taps filter" 
97187757758331343805c57b0d7a26f8 "Default TM1.1 100Mhz 30Khz FDD timedomain 245Msps waveform 2x 32taps filter new coeff (stop10000)" 
fd083a75a1181232ec95121d51698c5d "Default TM1.1 100Mhz 30Khz TDD timedomain 245Msps waveform 2x 32taps filter new coeff (stop10000)" 
7813cf27c9a363fcec832d48ec965abe "Default TM3.3 100Mhz 30Khz FDD timedomain 245Msps waveform 2x 32taps filter QEC coeff applied." 
f0c3f03b5e366cbdefd8f34ec66b0889 "Default TM3.1 100Mhz 30Khz FDD CFR disabled DPD output waveform." 
d2a51a5a784aebafb446fcb7529826e2 "Default TM3.3 100Mhz 30Khz FDD timedomain 491Msps waveform 2x 32taps filter" 
9259eb5fe12ba6abe912a2cecee6dc80 "Default TM1.1 100Mhz 30Khz FDD timedomain 491Msps waveform 2x 32taps filter new coeff (stop10000)" 
e456c0420fd1d340de81e3fb7f19d96c "Default TM1.1 100Mhz 30Khz TDD timedomain 491Msps waveform 2x 32taps filter new coeff (stop10000)" 
4e5cf279fe93e48b87822c458ffd6d74 "Default TM3.3 100Mhz 30Khz FDD time domain 491Msps waveform Diora Coeff applied." 
aec2905f3096a3713d30818965071165 "Default TM3.3 100Mhz 30Khz FDD timedomain new 4x64taps(stop1000) 491Msps waveform 10ms input 20ms dump" 
4ba616268406a56f6ac59b8313f0d685 "Default TM3.3 100Mhz 30Khz FDD DPD output Diora Coeff applied waveform." 
8d9364c55f225b445b11ff416e71f764 "Default TM3.3 100Mhz 30Khz TDD DPD output Diora Coeff applied waveform." 
b71d7cb9a6da811f58b3d66c1b4ab9c9 "Default TM3.3 100Mhz 30Khz FDD DPD Diora Coeff applied waveform." 
40429e22ce0b3d0d1e41fbc88a794a57 "Default TM3.3 100Mhz 30Khz FDD 4x64 taps upsampling DPD Diora Coeff applied waveform." 
9c241674242818bb02f1f00bcfe833fe "Default TM3.3 100Mhz 30Khz TDD DPD Diora Coeff applied waveform." 
83d7512b3a6bf09b07139d00982a3903 "Default TM1.1 100Mhz 30Khz FDD waveform." 
c8f0a1fc0acab02f8568c6b24e6e22b8 "Default TM3.3 100Mhz 30Khz FDD waveform at 1.9Gsps." 
47b7cd78803664cfa725546d47c0c45d "Default TM3.3 100Mhz 30Khz TDD waveform at 1.9Gsps." 
ce848473b2bbdcf39d45d6efd7032fa2 "Default TM3.3 100Mhz 30Khz FDD CFR All 3PASS enabled waveform." 
9abe3648ef4a1973b9a82cff6f07881f "Default TM3.3 100Mhz 30Khz FDD time domain 491Msps QEC coeff updated waveform." 
ccd03b0c29bedc68ef8e915c5f9dc856 "Default TM3.3 100Mhz 30Khz FDD 1x time domain injection CFR All 3PASS enabled waveform." 
383c62a0f90876a8b59f4ae988c2e5ab "Default TM3.3 100Mhz 30Khz FDD CFR All 3PASS enabled DPD output waveform." 
58fdbe30b091da4e7861d1a62bcdb479 "Default TM3.3 100Mhz 30Khz FDD compressed waveform." 
f41292320acc84f9581e3d4d39bd64c1 "Default TM3.3 100Mhz 30Khz FDD 9-bit compressed waveform." 
637f035f0858b6ec73cac3433934f706 "Default TM3.1 100Mhz 30Khz FDD 4x32 taps upsampling waveform." 
a42bb97ef3ce63c399ef1a6d3b17662f "Default TM3.1 200Mhz 60Khz TDD 4x32 taps upsampling waveform." 
8285eb0cb985d6e420bd5e737f0f46f2 "Default TM3.1 200Mhz 60Khz FDD 4x32 taps upsampling waveform." 
050884b38de317181e869863ad0fa73b "Default TM3.1 200Mhz 60Khz FDD time domain 245Msps waveform." 
b40fe808a136bad274afd190f20a6e36 "Default TM3.1 200Mhz 60Khz FDD time domain 245Msps waveform." 
a5cd36afc72c546f015e4beaed41b846 "Default TM3.1 400Mhz 120Khz TDD 2x16+2x16 taps upsampling waveform." 
cd7208336d091f6135354674d2a55650 "Default TM3.1 400Mhz 120Khz TDD 2x16 upsampling + 2x duplicate waveform." 
65690ce2845e55764124f263a25c37c9 "Default TM3.1 400Mhz 120Khz TDD 4x32 taps upsampling waveform." 
046206445896c904056f8432351d8973 "Default TM3.1 400Mhz 120Khz FDD 2x16+2x16 taps upsampling waveform." 
8b9a8ab8459bc819b7a7d698168d6307 "Default TM3.1 400Mhz 120Khz FDD waveform 983Msps." 
3cc441580a6e6d979aedfebe1ff10473 "Default TM3.1 400Mhz 120Khz FDD 4x32 taps upsampling waveform QEC passthrough." 

facf1385cce659885955e29117f587e6 "Default TM3.1 400Mhz 120Khz TDD 4x32 new taps upsampling waveform" 
bd7081155f5772d86d9e96866cb2c0f7 "Default TM3.1 400Mhz 120Khz TDD 4x32 new taps upsampling waveform(stop10000) 20ms dump." 
4c95e170f51ac730da49742c7a64baec "Default TM3.1 400Mhz 120Khz TDD 4x32 new taps upsampling waveform(stop10000) 1ms dump" 
2704bd8db31ca7a072894511437ee06b "Default TM3.1 400Mhz 120Khz TDD 4x32 new taps upsampling waveform(stop10000) scaled 125% 1ms dump" 
71abfc604d0f70233a56de9b7ad78f72 "Default TM3.1 400Mhz 120Khz TDD 4x32 new taps upsampling waveform(stop10000) 1ms QEC imb applied dump" 
c59ffcfb6eebad66410b9a97beeda307 "Default TM3.1 400Mhz 120Khz TDD 4x32 new taps upsampling waveform(stop10000) 1ms QEC imb+dc applied dump" 
81234103a3acadc12d24fe6e5099d1e5 "Default TM3.1 400Mhz 120Khz TDD 4x32 new taps upsampling waveform QEC passthrough used in FDD." 
bbde39044205705e6f2b26da96e46c1b "Default TM3.1 400Mhz 120Khz FDD 4x32 new taps upsampling waveform" 
83c2185fa701ba06e2a549ffcc1cf5d9 "Default TM3.1 400Mhz 120Khz FDD 4x32 new taps upsampling(stop10000) waveform 20ms dump" 
dc3861a5441fa9845ca9ab0a744940e6 "Default TM3.1 400Mhz 120Khz FDD 4x32 new taps upsampling(stop10000) waveform 1ms dump" 
87fb457908239ea6fc32e883b53d6b2e "Default TM3.1 400Mhz 120Khz FDD 4x32 new taps upsampling(stop10000) waveform scaled 125% 1ms dump" 
f31a5757793de34a4acb219d0985ef77 "Default TM3.1 400Mhz 120Khz FDD 4x32 new taps upsampling(stop10000) waveform 1ms dump QEC imb applied" 
eaf2aab778a31b382a9e3690bbd1afad "Default TM3.1 400Mhz 120Khz FDD 4x32 new taps upsampling(stop10000) waveform 1ms dump QEC imb+dc applied" 
717e8f5f3e5895fadcb7e7e95f91f2e7 "Default TM3.1 400Mhz 120Khz FDD 4x32 new taps upsampling waveform QEC applied." 
c343468e1ca469fd2932f7a8518c280a "Default TM3.1 400Mhz 120Khz FDD 4x32 new taps upsampling TX looped back to RX freq dump." 
965be0fb5e73b41919a2ed7fc8ec8a92 "Default TM3.1 400Mhz 120Khz FDD 4x32 new taps upsampling(stop10000) TX looped back to RX freq dump." 

19dbed058effad93ae88708ab862a3a6 "Default TM3.1 400Mhz 120Khz FDD 4x32 taps upsampling waveform QEC coeff applied." 
356a89d0e0791e5dd4fef44ed2c74501 "Default TM3.1 100Mhz 120Khz TDD waveform." 
f226619bf7c9259ebd8deafdc5b671ef "Default TM3.1 100Mhz 120Khz TDD used for FDD waveform." 
fc5e39ec6926d5eff8733188b3d03574 "singletone 30Khz 25% scale LS FDD 491Msps 20ms dump" 
1b6224f58f123f7bdc75cad80f3278b7 "singletone 30Khz 25% scale LS FDD 122Msps 20ms dump" 
1a4dddf037c22d738468da28ce55fe11 "Singletone 30Khz+10Mhz 25% scale waveform LS FDD QEC passthrough" 
c3559693b8a77fa6c62b8655714e2ccd "single sub-carrier 30Khz 0x3FFF0x3FFF waveform LS FDD 20ms dump" 
ef72ef1ed76852f26a9840c8ea0c5e59 "single sub-carrier 30Khz+60Khz 0x3FFF0x3FFF waveform LS FDD 20ms dump" 
ef0be677df1daa0d35159b390ef6d446 "Singletone 30Khz 25% scale waveform LS FDD QEC applied 0 taps" 
8ae61e44089e705858c9fbb650d25cfc "Singletone 30Khz 25% scale waveform LS TDD 100Mhz SCS30 491Msps 20ms dump" 
ea6655db57d3e4043db816941e3e4f7f "Singletone 30Khz+10MHz 25% scale waveform LS TDD 100Mhz SCS30 491Msps 20ms dump" 
08b93b8d92f03fbf9a6c8a8919c8b18a "Single subcarrier 30Khz 25% scale waveform LS TDD 100Mhz SCS30 491Msps 20ms dump" 
cab202e15f7e6792022300b863f8b24f "Two subcarrier 30Khz+60Khz 25% scale waveform LS TDD 100Mhz SCS30 491Msps 20ms dump" 
032b014ab3e9dc595b3f9bd9f439f835 "Singletone 30Khz 25% scale waveform LS TDD QEC applied 0 taps" 
51d4344e25dabf6ea74a23c28ec5de64 "Two Singletones 30Khz 40% + 30Khz 40% scale waveform LS TDD" 
d99820d29dea759125216b6080633cc9 "Two Singletones 30Khz 40% + 60Khz 40% scale waveform LS TDD" 
45b678abd82417499a78b6eab2e72fe6 "Two Singletones 30Khz 40% + 60Khz 40% scale waveform LS TDD QEC applied 0 taps" 
6e2c63bcded6da67af6b615ebee1153b "Singletone 120Khz 25% scale waveform HS TDD 1.9Gsps 20ms dump" 
6cb2319014965eeb1a5c5374e9cfc1a9 "Singletone 120Khz 25% scale waveform HS FDD 1.9Gsps 20ms dump." 
41dd257c1bd353438df054fd7eaaf779 "Singletone 120Khz 25% scale waveform HS TDD 1.9Gsps 1ms dump." 
c0936b41d74cb9661fc18703eaa6f614 "Singletone 120Khz 25% scale waveform HS FDD 1.9Gsps 1ms dump" 
e170d94e3cd383d21fe8b310db8e2f37 "Singletone 120Khz 80% scale waveform HS TDD QEC applied 0 taps." 
1df065dcaef6d59378a612c5c4d6bfed "Two Singletones 120Khz 40% + 120Khz 40% scale waveform HS TDD" 
e89c198ca42c9d5fc5ce907dd996908c "Two Singletones 120Khz 40% + 240Khz 40% scale waveform HS TDD" 
0918b311c40507c74bfe96adb0bff24c "Two Singletones 120Khz 40% + 240Khz 40% scale waveform HS TDD QEC applied 0 taps" 
6edbc5cacc9d6074d40f33a5555da935 "Singletone 10Mhz 80% scale waveform HS FDD QEC passthrough" 

45e6fd10be3dd571e49b34256b539552 "Default TM3.1 800Mhz 480Khz FDD 10ms option8 2x16 taps filter 20ms timedomain dump waveform." 
48351f6a1fb78a58897f8b7b0c30cdf6 "20Mhz SCS30 61Msps LA9310 input with increasing counters FDD option8 dump"
9919537dbb63e5d037f7a4525086f783 "20Mhz SCS30 61Msps LA12xx input with increasing counters FDD option8 dump"
3944f053e152d29f40536481dc9d54d6 "1.9Gsps RX single tone 9960000Hz 1% scale freq domain reverse loopback 10ms buffer time domain 20ms dump"
098a5f81c79df2c1bee6b085aade5aee "1.9Gsps RX single tone 10Mhz 25% scale time domain 160KB buffer reverse loopback time domain 20ms dump"
e23c41dc7c830f5c42d4b0ddcb5f095d "1.9Gsps RX single tone 10Mhz 25% scale option8 0.5ms buffer reverse loopback time domain 20ms dump"
0)

ant=0
dump_dpd=0
dpdo=0; obs=0; obshschan=0
num_32K=0
size_hram=$((6*1024*1024))
offset_granul=0
dump_via_hram=0
force_ddr=0
mem=0
num_counter=0
offset=0
pow=0
hexd=0

arg_parse()
{
	arg=$1
	if 		[ $1 = dpdo ]; 	then		dump_dpd=1;	dpdo=1;dump_via_hram=1  #dpdo can only be dumped via HRAM with limited size
	elif 	[ $1 = obs ]; 	then		obs=1  #sync dump of observation path on LS
	elif 	[ $1 = obs4 ]; 	then		obs=1; obshschan=0  #sync dump of observation path on HSADC0
	elif 	[ $1 = obs5 ]; 	then		obs=1; obshschan=1  #sync dump of observation path on HSADC1
	elif 	[ $1 = mem ]; 	then		mem=1
	elif 	[ ${arg:0:7} = offset= ]; 	then		offset=${arg:7}; offset=$((offset)); [ $offset -gt $((0x3F)) ] && { echo -e "***ERROR: offset must be no larger than $((0x3F))\n"; exit 1; }
	elif 	([ $1 = HRAM ] || [ $1 = hram ]); 	then		dump_via_hram=1
	elif 	([ $1 = H2M ] || [ $1 = h2m ]); 	then		size_hram=$((2*1024*1024)); offset_granul=6; dump_via_hram=1
	elif 	([ $1 = DDR ] || [ $1 = ddr ]); 	then		force_ddr=1
	elif 	([ $1 = 0.5ms ] || [ $1 = .5ms ]); 	then		dump_time_len=0.5
	elif 	[ $1 = 1ms ]; 	then		dump_time_len=1
	elif 	[ $1 = 2ms ]; 	then		dump_time_len=2
	elif 	[ $1 = 5ms ]; 	then		dump_time_len=5
	elif 	[ $1 = 10ms ]; 	then		dump_time_len=10
	elif 	[ $1 = 20ms ]; 	then		dump_time_len=20
	elif 	[ $1 = 40ms ]; 	then		dump_time_len=40
	elif 	[ $1 = fast ]; 	then		fast=1
	elif 	[ $1 = hexd ]; 	then		hexd=1
	elif 	[ $1 = pow ]; then			pow=1
	else
		if [ $num_counter = 0 ];then	((num_counter++));	ant=$(get_ant_id_from_arg $1); [ $ant = null ] && { echo Wrong Argument: $1; print_usage; exit; }
		elif [ $num_counter = 1 ];then	((num_counter++));	num_32K=$(($1))
		else							echo Wrong Argument: $1; print_usage; exit
		fi
	fi
}

for i in "$@"
do
	arg_parse $i
done

[ $lphy = 1 ] && { echo -e "***ERROR: This command is not supported for option lphy.\n"; exit 1; }
([ $dpdo = 1 ] && [ $(((offset*32768)%40960)) -ne 0 ]) && { echo -e "***ERROR: offset must be multiple of 40960 for DPD dump, set offset to multiple of 5\n"; exit 1; }
[ $fr1_used = 0 ] && ant=$(((ant%2)+4))
obs=$((obs*2+obshschan)) #bit1=obs, bit0=ADC0/1
check_ant_enable_tx $ant #[ $((ant_enable[ant]&BITMASK_ANT_ENABLE_TX)) = 0 ] && { echo ***ERROR: Current TX ant $ant is not enabled.; exit 1; }

txcore=${anttx[$ant]}
tid=${tidant[$ant]}

get_chan_para $ant $txcore; [ $? != 0 ] && { echo -e "***ERROR: Failure Getting channel parameters\n"; exit 1; }
#[ $tx_timedomain_dump_inject_enable = 0 ] && { echo "***ERROR: Current version of VSPA image doesn't support this TX injecting or dumping."; exit 1; }

((sps=baseband_txsps*dpd_sps_ratio*dump_dpd+txaxiq*(1-dump_dpd))) #DPD works at 2x or 4x speed
end_hram=$next_HRAMaddr_phy
available_hram=$(((HRAMaddr_phy+HRAM_size-end_hram)/4096*4096))
addr_phy=$addr_dump
if [ $((dump_via_hram+force_ddr)) = 0 ];then
	([ $sps -ge 983040 ] || [ $baseband_txsps -ge 491520 ]) && dump_via_hram=1
fi

dpdinout=(input output)

if [ $dump_via_hram = 1 ];then 	
	if [ $size_hram -gt $available_hram ];then
		size_hram=$((available_hram/1024/1024))
		if [ $size_hram -ge 4 ]; then
			size_hram=$((4*1024*1024));	offset_granul=7;
		elif [ $size_hram -ge 2 ]; then
			size_hram=$((2*1024*1024));	offset_granul=6;
		elif [ $size_hram -ge 1 ]; then
			size_hram=$((1*1024*1024));	offset_granul=5;
		else
			echo Available HRAM size $available_hram is too small to use. command failed; exit 1;
		fi
	fi
fi
str=""
[ $dump_time_len = 0.5 ] && dump_time_len_double=1 || dump_time_len_double=$((dump_time_len*2))
if [ $dump_dpd = 0 ];then
	if [ $num_32K = 0 ];then
		((size=sps*4*$dump_time_len_double/2))
		size_tag=$dump_time_len\ms
		echo "Dumping TX time domain ant data $dump_time_len ms for antenna $ant ..."
	else
		if [ $num_32K -lt 1024 ];then
			((size=num_32K*32768))
			size_tag=$((num_32K*32))KB
			echo "Dumping TX time domain ant data $((num_32K*32)) KB for antenna $ant ..."
		else
			((size=num_32K))
			size_tag=$size
			echo "Dumping TX time domain ant data $size_tag for antenna $ant ..."
		fi
	fi
	dump_filename=tx_timedomain_$size_tag\_$sps\ksps_dump_ant$ant.bin
else
	[ $single_tone_stat = 1 ] && { echo ***Error: Current mode is single tone, DPD is not in working, please stop single tone; exit 1; }
	[ $dpd_model_id = 0 ] && { echo; echo ***Error: DPD is disabled in current version of test tool.; exit 1; }
	
	if [ $num_32K = 0 ];then
		((size=sps*4*$dump_time_len_double/2))
		size_tag=$((dump_time_len))ms
	else
		if [ $num_32K -lt 8192 ];then
			((size=num_32K*32768))
			size_tag=$((num_32K*32))KB
		else
			((size=num_32K))
			size_tag=$size
		fi
	fi
	if [ $((dump_via_hram*size)) -gt $((size_hram)) ];then
		echo ***WARNING: DPD output dump via HRAM with size $size. Will limit size to available size $size_hram.
		((size=size_hram))
		size_tag=$((size_hram/1024/1024))MB
	fi
	
	dump_filename=tx_timedomain_$size_tag\_DPD${dpdinout[$dpdo]}_$sps\ksps_dump_ant$ant.bin
	echo "Dumping TX time domain DPD ${dpdinout[$dpdo]} data $size_tag for antenna $ant ..."
fi

size_32KB_aligned=$(((size+32767)/32768*32768))
extra_size=$((size_32KB_aligned-size))
([ $((dump_via_hram+force_ddr)) = 0 ] && [ $size_32KB_aligned -le $available_hram ]) && addr_phy=$((HRAMaddr_phy+HRAM_size-available_hram))

warn_saturated=""
dump_1time()
{
	malloc_for_dump $size_32KB_aligned
	addr_vir=`phy2vir $addr_phy`
	#echo dump_time_domain_tx_1time $txcore $tid `HEX $addr_phy` $addr_vir $size_32KB_aligned $dpdo $obs $offset
	dump_time_domain_tx_1time $txcore $tid $addr_phy $addr_vir $size_32KB_aligned $dpdo $obs $offset
	[ $? -ne 0 ] && exit 1
	[ $flag_deqec = 1 ] && [ $dpdo = 1 ] && { echo deqec; deqec $txcore $addr_vir $((size/4)); }
	[ -f $dump_filename ] && rm $dump_filename
	dumpfile $addr_vir $dump_filename $size
	
	if ([ $fast = 0 ] && [ $pow = 1 ]);then
		check_sample_power $addr_vir $((size/4))
	fi
}

dump_via_hram_mlti_times()
{
	addr_vir=`printf "0x%x" $((HRAMaddr_vir+6*1024*1024-size_hram))`
	((addr_phy=HRAMaddr_phy+6*1024*1024-size_hram))
	echo "Using HRAM size $size_hram starting from $addr_vir as intermediate buffer for dumping..."
	
	((num_chunks=size_32KB_aligned/size_hram))
	((size_left=size_32KB_aligned-num_chunks*size_hram))
	[ $size_left = 0 ] && { ((num_loop=num_chunks)); size_left=$size_hram; } || ((num_loop=num_chunks+1))
	[ $num_loop -ge 64 ] &&  { echo ***Error: HRAM available size $size_hram too small, num of blocks $num_loop must be less than 64.; exit 1; }
	
	[ -f $dump_filename ] && rm $dump_filename
	dump_type=0; [ $dpdo = 1 ] && dump_type=1; [ $((dpdo*obs)) -ne 0 ] && dump_type=3
	([ $dump_type -ne 0 ] && [ $num_loop -gt 1 ]) && { echo ***Error: DPDO dump does not support multiple times dump.; exit 1; }
	flag_addr=`get_dump_done_flag_addr $txcore $addr_ant_tx_dump`
	echo -n Dumping in progress, waiting...
	for ((i=0;i<$(($num_loop));i++))
	do
		echo -n "$(($i*100/num_loop))%"
		size0=$size_hram; size1=$size_hram
		if [ $((i)) -eq $((num_loop-1)) ];then
		size0=$size_left; size1=$((size_left-extra_size))
		fi
		msb=$((0x0A100000 + (tid<<15) + (dump_type<<12) + (offset_granul<<8) + i))
		lsb=$(( ((size0/32/1024)<<20) + (addr_phy>>12) ))
		lsb=$(printf 0x%x $lsb)
		
		[ $tx_fdd = 0 ] && clear_mem $addr_vir $size_hram
		./utils/memrw w 16 $flag_addr 0
		vspa_mbox send $txcore $host_vspa_mbox_id $msb $lsb
		wait_for_flag_change $flag_addr 0

		if [ $mem = 0 ];then
			dumpfile $addr_vir $dump_filename $size1   #dumpfile will append data to file
		fi
	done
	echo 100%
}

if [ $dump_via_hram = 1 ];then 	
	if [ $size_32KB_aligned -le $available_hram ];then
		addr_phy=$((HRAMaddr_phy+HRAM_size-available_hram)); dump_1time;
	else				
		[ $mem = 1 ] && { echo -e "***ERROR: Dumping to memory not supported as dumping size $size_32KB_aligned is larger than available HRAM size $available_hram.\n"; exit 1; }
		dump_via_hram_mlti_times
	fi
else 							dump_1time
fi
[ $fast = 0 ] && echo -e "$str"
if [ $mem = 0 ];then		echo -e "An $ant dump done, to address:$addr_vir size:$size, file:$dump_filename\n"
else						echo -e "An $ant dump done, to address:$addr_vir size:$size, sampling rate:$sps\n"
fi

[ $fast = 1 ] && exit
[ $mem = 1 ] && { check_error $ant; exit; }

[ $hexd = 1 ] && hexdump $dump_filename | head
checksum=`md5sum $dump_filename`
checksum=${checksum:0:32}
echo md5sum $checksum
check_known_waveform $checksum

if [ $checksumpass = 1 ];then
	print_tx_dump_check_correct
#elif [ $((single_tone_stat)) -eq 0 ];then
#	addr_vir=`phy2vir ${addr_tx_wv[$ant]}`
#	invecfile=${invecfile_cur[$ant]}
#	if ([ $((size_32KB_aligned/4/sps)) -eq 20 ] && [ -f $invecfile ]);then
#
#		echo TX timedomain dump data correctness unknown.
#		dumpedfile=input_vector_dumped_back.bin
#		echo dumping input vector file back from memory and checking...
#		dumpfile $addr_vir $dumpedfile $invecsize
#		checksum_vecdumped=`md5sum $dumpedfile`
#		rm $dumpedfile
#		checksum_vecdumped=${checksum_vecdumped:0:32}
#		checksum_vecoriginal=`md5sum $invecfile`
#		checksum_vecoriginal=${checksum_vecoriginal:0:32}
#		if [ $checksum_vecdumped = $checksum_vecoriginal ];then
#			echo Input vector data file in memory is correct, detected input vector in use is $invecfile
#			echo
#		else
#			echo Input vector data file in memory is unknown
#			echo
#		fi
#	fi
fi
echo -e "$warn_saturated"
check_error $ant
