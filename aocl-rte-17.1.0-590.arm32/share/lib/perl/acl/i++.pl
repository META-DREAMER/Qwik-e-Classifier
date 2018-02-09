# (C) 1992-2017 Intel Corporation.                            
# Intel, the Intel logo, Intel, MegaCore, NIOS II, Quartus and TalkBack words    
# and logos are trademarks of Intel Corporation or its subsidiaries in the U.S.  
# and/or other countries. Other marks and brands may be claimed as the property  
# of others. See Trademarks on intel.com for full list of Intel trademarks or    
# the Trademarks & Brands Names Database (if Intel) or See www.Intel.com/legal (if Altera) 
# Your use of Intel Corporation's design tools, logic functions and other        
# software and tools, and its AMPP partner logic functions, and any output       
# files any of the foregoing (including device programming or simulation         
# files), and any associated documentation or information are expressly subject  
# to the terms and conditions of the Altera Program License Subscription         
# Agreement, Intel MegaCore Function License Agreement, or other applicable      
# license agreement, including, without limitation, that your use is for the     
# sole purpose of programming logic devices manufactured by Intel and sold by    
# Intel or its authorized distributors.  Please refer to the applicable          
# agreement for further details.                                                 


# Intel(R) FPGA SDK for HLS compilation.
#  Inputs:  A mix of sorce files and object filse
#  Output:  A subdirectory containing: 
#              Design template
#              Verilog source for the kernels
#              System definition header file
#
# 
# Example:
#     Command:       i++ foo.cpp bar.c fum.o -lm -I../inc
#     Generates:     
#        Subdirectory a.prj including key files:
#           *.v
#           <something>.qsf   - Quartus project settings
#           <something>.sopc  - SOPC Builder project settings
#           kernel_system.tcl - SOPC Builder TCL script for kernel_system.qsys 
#           system.tcl        - SOPC Builder TCL script
#
# vim: set ts=2 sw=2 et

      BEGIN { 
         unshift @INC,
            (grep { -d $_ }
               (map { $ENV{"INTELFPGAOCLSDKROOT"}.$_ }
                  qw(
                     /host/windows64/bin/perl/lib/MSWin32-x64-multi-thread
                     /host/windows64/bin/perl/lib
                     /share/lib/perl
                     /share/lib/perl/5.8.8 ) ) );
      };


use strict;
require acl::File;
require acl::Pkg;
require acl::Env;
require acl::Report;
use acl::Report qw(escape_string);

#Always get the start time in case we want to measure time
my $main_start_time = time(); 

my $prog = 'i++';
my $return_status = 0;

#Filenames
my @source_list = ();
my @object_list = ();
my @tmpobject_list = ();
my @fpga_IR_list = ();
my @cleanup_list = ();
my @component_names = ();

my $project_name = undef;
my $keep_log = 0;
my $project_log = undef;
my $executable = undef;
my $optinfile = undef;
my $pkg = undef;

#directories
my $orig_dir = undef; # path of original working directory.
my $g_work_dir = undef; # path of the project working directory as is.
my $quartus_work_dir = "quartus";
my $cosim_work_dir = "verification";

# Executables
my $clang_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin".'/aocl-clang';
my $opt_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin".'/aocl-opt';
my $link_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin".'/aocl-link';
my $llc_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin".'/aocl-llc';
my $sysinteg_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin".'/system_integrator';
my $mslink_exe = 'link.exe';

#Names
my $prj_name_section ='.prjnam'; # Keep section names of 7 char or less for COFF
my $fpga_IR_section ='.fpgaIR'; 
my $fpga_dep_section ='.fpga.d'; 

#Flow control
my $emulator_flow = 0;
my $simulator_flow = 0;
my $RTL_only_flow_modifier = 0;
my $object_only_flow_modifier = 0;
my $soft_ip_c_flow_modifier = 0; # Hidden option for soft IP compilation
my $x86_linkstep_only = 0;
my $cosim_linkstep_only = 0;
my $preprocess_only = 0;
my $macro_type_string = "";
my $cosim_debug = 0;
my $cosim_log_call_count = 0;
my $march_set = 0;

# Quartus Compile Flow
my $qii_project_name = "quartus_compile";
my $qii_flow = 0;
my $qii_vpins = 1;
my $qii_io_regs = 1;
my $qii_seed = undef;
my $qii_fmax_constraint = undef;
my $qii_dsp_packed = 0; #if enabled, force aggressive DSP packing for Quartus compile results (ARRIA 10 only)
my $g_quartus_version_str = undef; # Do not directly use this variable, use the quartus_version_str() function

# Device information
my $dev_part = undef;
my $dev_family = undef;
my $dev_speed = undef;
my $dev_device = "Arria 10";

# Supported devices
### list of supported families
my $SV_family  = "Stratix V";
my $CV_family  = "Cyclone V";
my $A10_family = "Arria 10";
my $M10_family = "MAX 10";
my $S10_family = "Stratix 10";
my $AV_family  = "Arria V";
my $C10_family = "Cyclone 10 GX";

### the associated reference boards
my %family_to_board_map = (
    $SV_family  => 'SV.xml',
    $CV_family  => 'CV.xml',
    $M10_family => 'M10.xml',
    $A10_family => 'A10.xml',
    $S10_family => 'S10.xml',
    $AV_family  => 'AV.xml',
    $C10_family => 'C10.xml',
  );

### unofficial family support for Megacore
my $AVGZ_family  = "Arria V GZ";
my $AIIGZ_family = "Arria II GZ";
my $SIV_family   = "Stratix IV";

my %unofficial_family_to_board_map = (
    $AVGZ_family  => 'SV.xml',
    $AIIGZ_family => 'SV.xml',
    $SIV_family   => 'SV.xml',
  );

# Flow modifier
my $target_x86 = 0; # Hidden option for soft IP compilation to target x86

# Simulators
my $cosim_simulator = "MODELSIM";
my $cosim_64bit = undef; # Avoid using this variable directly, use query_vsim_arch()
my $vsim_version_string = undef; # Avoid using this variable directory, use query_vsim_version_string()

#Output control
my $verbose = 0; # Note: there are three verbosity levels now 1, 2 and 3
my $disassemble = 0; # Hidden option to disassemble the IR
my $dotfiles = 0;
my $pipeline_viewer = 0;
my $save_tmps = 0;
my $debug_symbols = 1;      # Debug info enabled by default. Use -g0 to disable.
my $user_required_debug_symbol = 0; #User explicitly uses -g from the comand line.
my $time_log = undef; # Time various stages of the flow; if not undef, it is a 
                      # file handle (could be STDOUT) to which the output is printed to.

#Testbench names
my $tbname = 'tb';

#Command line support
my @cmd_list = ();
my @parseflags=();
my @linkflags=();
my @additional_opt_args   = (); # Extra options for opt, after regular options.
my @additional_llc_args   = ();
my @additional_sysinteg_args = ();
my $all_ipp_args = undef;

my $opt_passes = '--acle ljg7wk8o12ectgfpthjmnj8xmgf1qb17frkzwewi22etqs0o0cvorlvczrk7mipp8xd3egwiyx713svzw3kmlt8clxdbqoypaxbbyw0oygu1nsyzekh3nt0x0jpsmvypfxguwwdo880qqk8pachqllyc18a7q3wp12j7eqwipxw13swz1bp7tk71wyb3rb17frk3egwiy2e7qjwoe3bkny8xrrdbq1w7ljg70g0o1xlbmupoecdfluu3xxf7l3dogxfs0lvm7jlzmh8pv3kzlkjxz2acnczpy2g1wkvi7jlzmrpouhh3qrjxlga33czpygdbwgpin2t13svzq3kzmtfxmxffmowonxdb0uui32q3mju7atjmnjvbzxdsmczpyrkf0evzexy1qgfpt3gznj0318a7mcporxgbyw0oprlemyy7atj7me0b1rauqiypfrj38uui3rukqa0od3gbnfvc2xd33czpyrf70tji1guolg0odcvorlvc8xfbqb17frkb0t8zp2t13svzttdoluu3xxfhmivolgfbyw0o7xtclgvz0cvorlvcngfml8yplgf38uui32qqquwotthsly8xxgd33czpyrfu0evzp2qmqwvzltk72tfxm2dblijzm2hfwwpowxyolu07ekh3nupb3rkmni8pdxdu0wyi880qqkvot3jfnupblgd3lo87frk77gpo880qqkyzuhdfnfy3xxf7m88zt8vs0r0zb2lcna8pl3aorlvcvgsmmvyzsxg7etfmiresqryp83bknywbp2kbmb0zgggzwtfmirebmrwo23g1nhwb1rkmniworrj1wkpioglctgfpttjhljpb1ra1q38zq2vs0rvzrrlcljjzucfqnldx0jpsmvjog2g3eepin2tzmhjzy1bkny8xxxkcnvvpagkuwwdo880qqkwou3gfny8cvrabqoypaxbbyw0ot2qumywpkhkqmydc3rzbtijz12j10g0zorekqjwoecvorlvcvxafq187frkm7wjz1xy1mju7atjfnevcbrzbtijzsrgfwhdmire1nsvom3gzmy0x18a7q3wp12j7eqwipxw13swz8bvorlvcvxafq187frkbew0zq2q3lk0py1bkny8xxxkcnvvpagkuwwdo880qqk8packbmupbqrzbtijzsrgfwhdmirekmg8ps3h72tfxmrafmiwoljg7wudop2w3ldjpacvorlvc32jsqb17frkk0udi3xukls0o0cvorlvcqxf7q1w7ljg70qyitxyzqsypr3gknt0318a7qp8oaxfbyw0owxqolg8zw3gknr0318a7mvvp1gfbwepow2w3qgfptcd1ml0b7xd1q3ypdgg38uui3xwzlg07ekh3nuwcmgd33czpyrfu0evzp2qmqwvzltk72tfxmgssm80oyrgkwrpii2wctgfpttdzqj8xwgpsmv0zl2kc0uui3xuolswoscfqqkycqrzbtijzwxgfwrpopxwzqg07ekh3nyjxxxkcno8z1rjbwtfmireoqjpo23golj0318a7mvvpfgdbwgjz7jlzqdjp2ckorlvczxazl887frkc7wdmirekmswo23gknj8xmxk33czpyxgf0jdor20qqk0okcdonj0318a7m3pp1rghwedmirezmd8zahholqvb0jpsmv0zwgdb7uvm7jlzmajpscdorlvcqgskq10pggjuetfmiretqkvo33j72tfxmrafmiwoljg70kyirrltma07ekh3nedxqrj7mi8pu2hs0uvm7jlzmg8iahp3qh8cyrzbtijza2k77lpo1x713svz33gslkwxz2dunvpzwxbbyw0otrezmy07ekh3nrdbxrzbtijza2jk0rvzkrlcnr07ekh3nedxqrj7mi8pu2hs0uvm7jlzmfyofcdorlvcyrsmncyzq2hs0yvm7jlzmgvoecvorlvc7rd7mcw7ljg70gpizxutqddzbtjbnr0318a7mzpp8xd70wdi22qqqg07ekh3njwblgs3nczpyxjb0tjo7jlzmyposcfhlh8vwgd7lb17frkzwewi22etmgvzecvorlvcmxasm80oa2jm7ydo880qqkpzuhd1meyclrzbtijzlgju0uui3xueqddp03k1mtfxmgfmnx87frk1wwpop2tzldvoy1bkny8cvxj1m7joljg70qyip2qqqg07ekh3lljxlgamnc0ot8vs0rdi7gu7qgpoecfoqjdx0jpsmvypfxdbwgyo1re1qu07ekh3ltjcrgjbqb17frk3egwizrl3lgvo03jzmevcqrzbtijzrrkh0uui3xleqjwzekh3njwbc2kbmczpy2hswk8zbglzldvz33bkny8c8rd33czpyxh1wwjop2w13svzehkqny8cvra7lb17frkcegpoirumqspof3bknyyc2gs7mb0psrf38uui3xleqtyz2tjhlldb0jpsmv0zy2j38uui3xleqtyz2tjhllvbyrzbtijzrxgz7tppt20qqkpoe3hhlgyc18a7mo8za2vs0rpiixyolddp33g3nj0318a7q88zargo7udmireeqspzekh3nuvcmgd7n88z8xbbyw0o0re1mju7atj3my8cvgfml88z3xg38uui3xwzqg07ekh3lkpbz2jmr88zwxbbyw0or2wuqsdoe3bkny8xxgscnzyzs2hq7tjzbrlqqgfpttdzmlpb1xk33czpyxfm7wdioxy1mypokhf72tfxmgfcmv8zt8vs0rjiorlclgfpttdqnq0bvgsom7w7ljg7whvib20qqkvzs3jfntvbmgssmxw7ljg70gpizxutqddzbtjbnr0318a7mzpp8xd70wdi22qqqg07ekh3ltvc1rzbtijzwxgfwrpopxwzqg07ekh3lr8xdgj3nczpygkuwk0o1ru3lu07ekh3lqyx1gabtijz8xfh0qjzw2wonju7atjmltwclgd7n887frk7ehpo32w13svzn3k1medcfrzbtijz72jm7qyokx713svzm3gzlh0x18a7m2yp82jbyw0oz2wolhyzy1bknywcmgd33czpy2kcek8zbge1nryz8hdhlk8c3gfcnzvpfxbbyw0omgyqmju7atjznrdbugd33czpyxj70uvm7jlzqu8pfcdfnedcfxfomxw7ljg7we0zwgu1lkwokhkqquu3xxfuqijomrkf0e8obgl1qgfpthhhntfxm2j33czpyrf70tji1gukmeyzekh3lq8clxdbmczpy2kz0y8z7rwbmryz3cvorlvcqxf1qoyz1gfbwhji880qqkwzt3k72tfxm2duq78o32vs0r8obxyzqjvo0td72tfxmrafm28z1rfz7qjz3xqctgfpttd3nuwx72kuq08zt8vs0ryioguumavoy1bknywcmgd33czpy2kc0rdo880qqkjznhh72tfxmrd7mcw7ljg70qyitxyzqsypr3gknt0318a7q1dodrjm7tdi7jlzqhwpshjmlqy3xxfkmc8pt8vs0rvzrrl7mu8zf3bknyjcvxammb0pljg70edoz20qqkyo33jcnt0318a7q3doggdu0tji7jlzqa8z0cg72tfxmxdoliw7ljg70gpizxutqddzb3bknydcwrzbtijzqrkbwtfmirekmswzeca3mg8cwrkuqivzt8vs0rwzb2qzqa07ekh3lhpb72a7lxvp12gbyw0oygukmswolcvorlvcvxafq187frk77qdiyxlkmh8iy1bknywxmxk7nbw7ljg70edoprlemy07ekh3lgyclgsom7w7ljg7wewioxu13svz33gslkwxz2dulb17frkh0r0zt2ectgfpthj1lrpb1gkbtijzrggs0wjz1xy1mju7atjznlwb18a7mvpzw2vs0r8o2gwolg8oy1bknypclgfsmvwpljg70rwiigy1muvokthklj7318a7qcjzlxbbyw0obglznrvzs3h1nedx1rzbtijz3xhu0uui3reeqjwpetd3nedx3rzbtijz72j7wkwir2qslgy7atjtntpbxgdhqb17frko7u8zbgwknju7atjclgdx0jpsmvypfrfc7rwizgekmsyzy1bknywcmgd33czpygdbwgpin2tctgfpthdonqjxrgdbtijzq2j1wudmireznrjp23k3quu3xxfcmv8zt8vs0rjiorlclgfptckolqycygsfqiw7ljg7wjdor2qmqw07ekh3nqyclxdbmczpyxfm7ujobrebmryzw3bknyvbyxamncjot8vs0rjo32wctgfpt3gknjwbmxakqvypf2j38uui3gu1mywpktjmlhyc18a7qojonxbbyw0o1xwzqg07ekh3lq8xmga33czpyxgf0wvz7jlzqu8pfcdfnedcfrzbtijz12jk0wyz720qqkjz73j1qt0318a7qoypy2g38uui3xleqs0oekh3lhpbzrk7mi8ofxdbyw0o1glqqswoucfoluu3xxf7qvwot8vs0ryz7gukmh8iy1bkny8xxxkcnvvpagkuwwdo880qqkjznhh72tfxmxkumowos2ho0s0onrwctgfptchhngyclxkznz0oyxh38uui32l1mujzehdolhybl2a33czpyrfu0evzp2qmqwvzltk72tfxmrafm28z1rfz7qjz3xqctgfpttkbql0318a7q3doggdu0tji7jlzqa8z0cg72tfxmrd7mcw7ljg7wjdor2qmqw07ekh3ljyc8gj7mc87frkm7u0zo2yolkyz3cvorlvc8xfbqb17frko7u8zbgwknju7atjmltpxuxkcnczpyrfuwadotx713svz33gslkwxz2dunvpzwxbbyw0oprl7lgpo3tfqlhvcprzbtijzyxh1wwyi7xl13svzr3j1qj8x12kbtijzggg77u8zw2qems07ekh3lq8xmga33czpy2g3euvm7jlzqjdpathzmuwb1gpsmvjzd2kh0u0z32qqqhy7atj1nlybxrd7lb17frkz0uyi7gubmryzekh3nq8x2gpsmv8plxd1wupow2ectgfptcdqnyvx18a7mo8za2vs0r0ooglmqdjzy1bknydb12kuqxyit8vs0rjibreumju7atjcme8xmga33czpyxgf0tjotxyemuyz3cfqqqyc0jpsmv0p0rjh0qyit2wonr07ekh3ljycbgfcncdog2kh0q8p7x713svzwtjoluu3xxfmmbdo12hbwg0zw2ttqg07ekh3ltvc1rzbtijz12jceqwzqrwkmg07ekh3ng8xxrzbtijz0rgm7lpiw2wuqgfpt3gklhpbz2a7nzjz82vs0rjiory1muyz2cvorlvcbgdkmidoxrfcegdo12lkmsjzy1bknywxcgfcm80odgfb0gjzkxl1mju7atj3my8cvgfml88zq2d7wkpioglctgfpttjhlldb12kcnczpy2hswkdom2wolgfpt3hoqqwbzrkhmz8z1rf38uui32qqquwotthsly8xxgd33czpyxj70uvm7jlzqjwzg3f3qhy3xxf7nzdilrf38uui3gy1mu8pl3a72tfxm2d3nczpyxfb7gvi7jlzqayovcvorlvc2rkbtijzh2kmeudoi2w3mju7atjbnhvb1gpsmv0o12hz0wyio2l1mrpoktjorlvc2gjsmv0ogrgs0gvm7jlzmhyo33korlvc7rdcm88ou2vs0ryoeglzmr8pshh3quu3xxfcmi8ouxgb0uui3xu1la0oekh3lr0b18a7m3ppgxd38uui32qqquwotthsly8xxgd33czpyxj70uvm7jlzmh0ot3bknywc1xffmowodrfuwkpioglctgfpt3gknjwbmxakqvypf2j38uui3xwzqg07ekh3lr0bmgpsmvjzdggo7u8zt2qemsy7atj7mhvbprzbtijzexf70uui3reemsdoehd3mejxxgpsmvdol2gfwjpopx713svzkhh3qhvccgammzpplxbbyw0o0re1mju7atjblkvc18a7qcyif2kk0q0o7jlzqjwpktkkluu3xxfuqijomrkf0e8obgl1mju7atjznyyc0jpsmvvz7gg38uui3rukqa0od3gbnfvc2xd33czpyxgf0jdorru7ldwotcg72tfxmxkumowos2ho0sdmiremmy07ekh3ltvc1rzbtijzggg7ek0oo2loqddpecvorlvc8xfbqb17frkh0wwiy20qqkvok3h7qq8x2gh33czpygfbwudz32w13svzw3k7mtdx8gdsmv8zljg7wupitxybmsvzecvorlvc72kmnbyiljg7wh8zbgyctgfpthdonqjxrgdbtijznggz7tyiw2w3qgfpttjmlqwxqrzbtijzsrg1wu0zwrlolgvo03afnt0318a7q8vpsxgbyw0oy2qclgwpkhholuu3xxfuqijomrkf0e8obgl1mju7atjznyyc0jpsmv0pg2guwkdmirezqsdpt3f1qjycxxfulb17frk1wwyioxybmryzekh3nqycbrdbq1w7ljg70qyit2wonry7atj3mfdxmgpsmvdzngjo0u8ztx713svzuhhknlwb7rjbmczpyrkt0tyii2wtqgfptckolkycxrdbqijzg2j7etfmirebmsdpscfmlhyc18a7qx8zfrkb0uui3xw1myvoy1bknydcwxd1mzppqgd1wg0z880qqkvok3h7qq8x2gh7qxvzt8vs0rjiory1muvom3gzmy0x0jpsmv0pdrg37uui3rukqa0od3gbnf0318a7qovpdxfbyw0o3rlumk8pa3k72tfxm2kbqc8oy2jbyw0o02wclgdpw3kknyyc18a7qcyp8xd1ww0o7x713svz33gslkwxz2dunvpzwxbbyw0oprl7lgpo3tfqlhvcprzbtijzqrkbwtfmiremlgpokhkqquu3xxf7nvyp7xbbyw0ongw7ng07ekh3njwxrrzbtijzu2hc7uui32lbms8p8cvorlvcw2kbmczpyxgf0wvz7jlzmy8p83kfnedxz2azqb17frkm7udiogy1qgfptckoqkwxzxf1q38zljg7wu8omx713svzqhfkluu3xxfuqijomrkf0e8obgl1mju7atjznedxygd33czpy2kc0rdo880qqkvot3gbquu3xxfhmivp32vs0rvzbxu1ma8pa3gknr0318a7mzpp8xd70wdi22qqqg07ekh3ltvc1rzbtijz12jk0wyz720qqkwz7cdfnevc7rjbmczpyxjm0yvm7jlzqu8pfcdfnedcfxfomxw7ljg7wewiq2wolujokcf3le0318a7qcvpm2vs0r0onrw13svzdthhlky3xxf3nzwolxguwwpiirwctgfpttkolky3xxfhmivolgfuwwwo880qqk8patdzmyjxb2fuqi8zt8vs0r0zb2lcna8pl3a3lrjc0jpsmv0pdrdbwg0zq2q3lk0py1bknywcmgd33czpygj37uui3xqbmuwzehholty3xxf1mvjzn2g38uui3gwclgfptcgmljwc12abqc87frkc0wjz880qqk8patdzmyjxb2fuqi8zt8vs0r0zb2lcna8pl3a3lrjc0jpsmv0pdrdbwg0zq2q3lk0py1bknywcmgd33czpy2kcwldztxy13svz33gumtvb0jpsmvpolgfuwypp880qqkdzdthmlh8xxxd3niypfxd7ekppp2wctgfpttd7qq8xygpsmvjzh2kswwdopructgfptck3nt0318a7q28z12ho0svm7jlzqg0i8th3mty3xxfhmzpol2vs0ryz1xl1lgvoy1bknyvb2xfbtijzggg7ekdmireemuwzehdqlljc0jpsmvjz12j1wkdo7jlzquwouchfntfxm2dmnc8zljg70rjieru3lgpo3cvorlvcqgdhmcjzm2vs0r0ov2ekmsy7atjhlkwb0jpsmv0zy2j38uui32qqquwotthsly8xxgd33czpy2kcwldztxy13svz33gumtvb0jpsmvpolgfuwypp880qqkpz23kmnwy3xxfkmc8pq2j3etfmire3qkyzy1bknypb1rdbnv8zljg7wypoirl1nr07ekh3ljycqxabl8jzl2vs0r0zv2eolddpqcvorlvcogdmli8zs2vs0ryoogu13svzu3fzmlpbu2abtijz3gffwypip2qqqh07ekh3nywx1gfsm3woljg70gwinxy13svzkcd72tfxmrjtq8vpnrjtwhdzw20qqk0o23gklh0318a7q28z12ho0svm7jlzmh0oq3jbmtpbz2dulbz0f';

# Default output file extension
my $default_object_extension = ".o";

# device spec differs from board spec since it
# can only contain device information (no board specific parameters,
# like memory interfaces, etc)
my @llvm_board_option = ();

# cache result for link.exe checking
my $link_exe_exist = "unknown"; # value could be "unknown", "yes", "no"

# checks host OS, returns true for linux, false for windows.
sub isLinuxOS {
    if ($^O eq 'linux') {
      return 1; 
    }
    return;
}

# checks for Windows host OS. Returns true if Windows, false if Linux.
# Uses isLinuxOS so OS check is isolated in single function.
sub isWindowsOS {
    if (isLinuxOS()) {
      return;
    }
    return 1;
}

sub mydie(@) {
    if(@_) {
        print STDERR "Error: ".join("\n",@_)."\n";
    }
    chdir $orig_dir if defined $orig_dir;
    push @cleanup_list, $project_log unless $keep_log;
    remove_named_files(@cleanup_list) unless $save_tmps;
    exit 1;
}

sub myexit(@) {
    if ($time_log) {
      log_time ('Total time ending @'.join("\n",@_), time() - $main_start_time);
      close ($time_log);
    }

    print STDERR 'Success: '.join("\n",@_)."\n" if $verbose>1;
    chdir $orig_dir if defined $orig_dir;
    push @cleanup_list, $project_log unless $keep_log;
    remove_named_files(@cleanup_list) unless $save_tmps;
    exit 0;
}

# These routines aim to minimize the system queries for paths
# by maintaining a "cached" copy of the paths, since these
# are static and do not change - this only need to be queried
# once.

# Global Library path names, since these are reused.
# These are only obtained once, only if undef'd.


# $abspath_mslink64 is obtained once, and not modified. 
# This path is used as the base to obtain paths to the
# Microsoft link libraries.
#
# All strings used for substitution operations here
# should be described in lowercase since the detected base paths
# are converted to lowercase.
#
my $abspath_mslink64 = undef;
my $str_mslink64 = 'bin/amd64/'.$mslink_exe;

my $abspath_libcpmt = undef;
my $abspath_msvcrt = undef;
my $abspath_msvcprt = undef;

# Similarly, $abspath_hlsbase points to the path
# for hls_vbase.lib, which is then used to obtain the
# paths for hls_emul and hls_cosim needed at link time.
my $abspath_hlsbase = undef;
my $str_hlsvbase = "/host/windows64/lib/hls_vbase\.lib";

my $abspath_hlscosim = undef;
my $abspath_hlsemul = undef;
my $abspath_hlsfixed_point_math_x86 = undef;
my $abspath_hlsvbase = undef;
my $abspath_mpir = undef;
my $abspath_mpfr = undef;

sub check_link_exe_existance {
  if ( $link_exe_exist eq "unknown" ){
      my $msvc_out = `$mslink_exe 2>&1`;
    chomp $msvc_out;
    if ($msvc_out !~ /Microsoft \(R\) Incremental Linker Version/ ) {
      $link_exe_exist = "no";
    }
    else {
      $link_exe_exist = "yes";
    }
  }

  if( $link_exe_exist eq "no" ){
    mydie("$prog: Can't find the Microsoft linker LINK.EXE. Make sure your Visual Studio is correctly installed and that it's linker can be found.\n");
  }

  # $link_exe_exist eq "yes"
  return 1;
}

sub get_mslink64_path {
    if (!defined $abspath_mslink64) {
      $abspath_mslink64 = acl::File::which_full($mslink_exe);
      chomp $abspath_mslink64;
      # lowercase the base string. All conversions are done in lower
      # case. Windows is case insensitive, but need to make sure
      # all substitution operations consistently in one case.
      $abspath_mslink64 = lc $abspath_mslink64;
    }
    return $abspath_mslink64;
}

sub get_hlsbase_path {
    if (!defined $abspath_hlsbase) {
      $abspath_hlsbase = acl::File::abs_path(acl::Env::sdk_root().'/host/windows64/lib/hls_vbase.lib');
      unless (-e $abspath_hlsbase) {
        mydie("HLS base libraries path does not exist\n");
      }
      # lowercase the base string. All conversions are done in lower
      # case. Windows is case insensitive, but need to make sure
      # all substitution operations consistently in one case.
      $abspath_hlsbase = lc $abspath_hlsbase;
    }
    return $abspath_hlsbase;
}

sub get_hlsvbase_path {
    if (!defined $abspath_hlsvbase) {
      get_hlsbase_path();
      $abspath_hlsvbase = $abspath_hlsbase;
      $abspath_hlsvbase =~ tr{\\}{/};
    }
    return $abspath_hlsvbase;
}

sub get_hlscosim_path {
    if (!defined $abspath_hlscosim) {
      get_hlsbase_path();
      $abspath_hlscosim = $abspath_hlsbase;
      $abspath_hlscosim =~ tr{\\}{/};
      my $str_hlscosim = "/host/windows64/lib/hls_cosim\.lib";
      $abspath_hlscosim =~ s/$str_hlsvbase/$str_hlscosim/g;
      unless (-e $abspath_hlscosim) {
        mydie("hls_cosim.lib does not exist!\n");
      }
    }
    return $abspath_hlscosim;
}

sub get_hlsemul_path {
    if (!defined $abspath_hlsemul) {
      get_hlsbase_path();
      $abspath_hlsemul = $abspath_hlsbase;
      $abspath_hlsemul =~ tr{\\}{/};
      my $str_hlsemul = "/host/windows64/lib/hls_emul\.lib";
      $abspath_hlsemul =~ s/$str_hlsvbase/$str_hlsemul/g;
      unless (-e $abspath_hlsemul) {
        mydie("hls_emul.lib does not exist!\n");
      }
    }
    return $abspath_hlsemul;
}

sub get_hlsfixed_point_math_x86_path {
    if (!defined $abspath_hlsfixed_point_math_x86) {
      get_hlsbase_path();
      $abspath_hlsfixed_point_math_x86 = $abspath_hlsbase;
      $abspath_hlsfixed_point_math_x86 =~ tr{\\}{/};
      my $str_hlsfixed_point_math_x86 = "/host/windows64/lib/hls_fixed_point_math_x86\.lib";
      $abspath_hlsfixed_point_math_x86 =~ s/$str_hlsvbase/$str_hlsfixed_point_math_x86/g;
      unless (-e $abspath_hlsfixed_point_math_x86) {
        mydie("hls_fixed_point_math_x86.lib does not exist!\n");
      }
    }
    return $abspath_hlsfixed_point_math_x86;
}

sub get_mpir_path {
    if (!defined $abspath_mpir) {
      get_hlsbase_path();
      $abspath_mpir = $abspath_hlsbase;
      $abspath_mpir =~ tr{\\}{/};
      my $str_mpir = "/host/windows64/lib/altera_mpir\.lib";
      $abspath_mpir =~ s/$str_hlsvbase/$str_mpir/g;
      unless (-e $abspath_mpir) {
        mydie("altera_mpir.lib does not exist!\n");
      }
    }
    return $abspath_mpir;
}

sub get_mpfr_path {
    if (!defined $abspath_mpfr) {
      get_hlsbase_path();
      $abspath_mpfr = $abspath_hlsbase;
      $abspath_mpfr =~ tr{\\}{/};
      my $str_mpfr = "/host/windows64/lib/altera_mpfr\.lib";
      $abspath_mpfr =~ s/$str_hlsvbase/$str_mpfr/g;
      unless (-e $abspath_mpfr) {
        mydie("altera_mpfr.lib does not exist!\n");
      }
    }
    return $abspath_mpfr;
}

sub get_libcpmt_path {
    if (!defined $abspath_libcpmt) {
      get_mslink64_path();
      $abspath_libcpmt = $abspath_mslink64;
      $abspath_libcpmt =~ tr{\\}{/};
      my $str_libcpmt = "lib/amd64/libcpmt.lib";
      $abspath_libcpmt =~ s/$str_mslink64/$str_libcpmt/g;
      unless (-e $abspath_libcpmt) {
        mydie("libcpmt.lib does not exist\n");
      }
    }
    return $abspath_libcpmt;
}

sub get_msvcrt_path {
    if (!defined $abspath_msvcrt) {
      get_mslink64_path();
      $abspath_msvcrt = $abspath_mslink64;
      $abspath_msvcrt =~ tr{\\}{/};
      my $str_msvcrt = "lib/amd64/msvcrt.lib";
      $abspath_msvcrt =~ s/$str_mslink64/$str_msvcrt/g;
      unless (-e $abspath_msvcrt) {
        mydie("msvcrt.lib does not exist\n");
      }
    }
    return $abspath_msvcrt;
}

sub get_msvcprt_path {
    if (!defined $abspath_msvcprt) {
      get_mslink64_path();
      $abspath_msvcprt = $abspath_mslink64;
      $abspath_msvcprt =~ tr{\\}{/};
      my $str_msvcprt = "lib/amd64/msvcprt.lib";
      $abspath_msvcprt =~ s/$str_mslink64/$str_msvcprt/g;
      unless (-e $abspath_msvcprt) {
        mydie("msvcprt.lib does not exist\n");
      }
    }
    return $abspath_msvcprt;
}

sub create_empty_objectfile($$) {
    my ($object_file, $dummy_file) = @_;
    my @cmd_list = undef;
    if (isLinuxOS()) {
      # Create empty file by copying non-existing section from arbitrary 
      # non-empty file
      @cmd_list = ( 'objcopy',
                    '--binary-architecture=i386:x86-64',
                    '--only-section=.text',
                    '--input-target=binary',
                    '--output-target=elf64-x86-64',
                    $dummy_file,
                    $object_file
          );
    } else {
      @cmd_list = ('coffcopy.exe',
                   '--create-object-file',
                   $object_file
          );
    }
    mysystem_full({'title' => 'create object file'}, @cmd_list);
    if ($? != 0) {
      mydie("Not able to create $object_file");
    }
    push @object_list, $object_file;
}

sub add_section_to_object_file ($$$) {
    my ($object_file, $scn_name, $content_file) = @_;
    my @cmd_list = undef;
    unless (-e $object_file) {
      create_empty_objectfile($object_file,$content_file);
    }
    if (isLinuxOS()) {
      @cmd_list = ('objcopy',
                   '--add-section',
                   $scn_name.'='.$content_file,
                   $object_file
          );
    } else {
      @cmd_list = ('coffcopy.exe',
                   '--add-section',
                   $scn_name,
                   $content_file,
                   $object_file
          );
    }
    mysystem_full({'title' => 'Add IR to object file'}, @cmd_list);
    if ($? != 0) {
      mydie("Not able to update $object_file");
    }
    if (isLinuxOS()) {
      @cmd_list = ('objcopy',
                   '--set-section-flags',
                   $scn_name.'=alloc',
                   $object_file
          );
      mysystem_full({'title' => 'Change flags to object file'}, @cmd_list);
      if ($? != 0) {
        mydie("Not able to update $object_file");
      }
    }
    return 1;
}

sub add_projectname_to_object_file ($$$$) {
    my ($object_file, $scn_name, $content_file, $ref_file) = @_;
    open FILE, "<$ref_file"; 
    my $has_component = undef;
    while (my $line = <FILE>) {
      if($line =~ /hls.components = !{/) {
        if($line !~ /hls.components = !{}/) {
          $has_component=1;
        }
        last; 
      }
    }
    close FILE;
    if (!$has_component) {
      return;
    }
    unless (-e $object_file) {
      create_empty_objectfile($object_file,$content_file);
    }
    
    my @cmd_list = undef;
    if (isLinuxOS()) {
      @cmd_list = ('objcopy',
                   '--add-section',
                   $scn_name.'='.$content_file,
                   $object_file
          );
    } else {
      @cmd_list = ('coffcopy.exe',
                   '--add-section',
                   $scn_name,
                   $content_file,
                   $object_file );
    }
    mysystem_full({'title' => 'Add project dir name to object file'}, @cmd_list);
    if ($? != 0) {
      mydie("Not able to update $object_file");
    }
    if (isLinuxOS()){
      @cmd_list = ('objcopy',
                   '--set-section-flags',
                   $scn_name.'=alloc',
                   $object_file);
      mysystem_full({'title' => 'Change flags to object file'}, @cmd_list);
      if ($? != 0) {
        mydie("Not able to update $object_file");
      }
    }
}

sub get_section_from_object_file ($$$) {
    my ($object_file, $scn_name ,$dst_file) = @_;
    my @cmd_list = undef;
    if (isLinuxOS()) {
      @cmd_list = ('objcopy',
                   ,'-O', 'binary', 
                   '--only-section='.$scn_name,
                   $object_file,
                   $dst_file
          );
    } else {
      @cmd_list = ( 'coffcopy.exe',
                    '--get-section',
                    $scn_name,
                    $object_file,
                    $dst_file
          );
    }
    mysystem_full({'title' => 'Get IR from object file'}, @cmd_list);
    if ($? != 0) {
      mydie("Not able to extract $object_file");
    }
    return (! -z $dst_file);
}

sub get_project_directory_from_file(@) {
    my @filelist = @_;
    my $project_dir = undef;
    my $tmp_file = $$.'prj_name.txt';
    foreach my $filename (@filelist) {
      my @cmd_list = undef;
      if (isLinuxOS()){
        @cmd_list = ( 'objcopy',
                      '-O','binary',
                      '--only-section='.$prj_name_section,
                      $filename,
                      $tmp_file
        );
      } else {
        @cmd_list = ( 'coffcopy.exe',
                 '--get-section',
                 $prj_name_section,
                 $filename,
                 $tmp_file
            );
      }
      $return_status = mysystem_full({'title' => 'Get IRproject_name from object file'}, @cmd_list);
      if($return_status == 0){
        open FILE, "<$tmp_file"; binmode FILE; my $name =<FILE>; close FILE;
        if ($name) {
          if (!$project_dir) {
            $project_dir = $name;
          } elsif ($project_dir ne $name) {
            mydie("All Components must target the same project directory\n"."This compilation tries to create $project_dir and $name!\n");
          }
        }
      }
    }
    push @cleanup_list, $tmp_file;
    if ($project_dir) {
      return $project_dir;
    } elsif ($g_work_dir) { # IF we shortcircuted the object file ...
	return $g_work_dir;
    } else {
      return 'a.prj';
    }
}

# Functions to execute external commands, with various wrapper capabilities:
#   1. Logging
#   2. Time measurement
# Arguments:
#   @_[0] = { 
#       'stdout' => 'filename',   # optional
#        'title'  => 'string'     # used mydie and log 
#     }
#   @_[1..$#@_] = arguments of command to execute

sub mysystem_full($@) {
    my $opts = shift(@_);
    my @cmd = @_;

    my $out = $opts->{'stdout'};
    my $title = $opts->{'title'};
    my $err = $opts->{'stderr'};

    # Log the command to console if requested
    print STDOUT "============ ${title} ============\n" if $title && $verbose>1; 
    if ($verbose >= 2) {
      print join(' ',@cmd)."\n";
    }

    # Replace STDOUT/STDERR as requested.
    # Save the original handles.
    if($out) {
      open(OLD_STDOUT, ">&STDOUT") or mydie "Couldn't open STDOUT: $!";
      open(STDOUT, ">>$out") or mydie "Couldn't redirect STDOUT to $out: $!";
      $| = 1;
    }
    if($err) {
      open(OLD_STDERR, ">&STDERR") or mydie "Couldn't open STDERR: $!";
      open(STDERR, ">>$err") or mydie "Couldn't redirect STDERR to $err: $!";
      select(STDERR);
      $| = 1;
      select(STDOUT);
    }

    # Run the command.
    my $start_time = time();
    my $retcode = system(@cmd);
    my $end_time = time();

    # Restore STDOUT/STDERR if they were replaced.
    if($out) {
      close(STDOUT) or mydie "Couldn't close STDOUT: $!";
      open(STDOUT, ">&OLD_STDOUT") or mydie "Couldn't reopen STDOUT: $!";
    }
    if($err) {
      close(STDERR) or mydie "Couldn't close STDERR: $!";
      open(STDERR, ">&OLD_STDERR") or mydie "Couldn't reopen STDERR: $!";
    }

    # Dump out time taken if we're tracking time.
    if ($time_log) {
      if (!$title) {
        # Just use the command as the label.
        $title = join(' ',@cmd);
      }
      log_time ($title, $end_time - $start_time);
    }

    my $result = $retcode >> 8;

    if($retcode != 0) {
      if ($result == 0) {
        # We probably died on an assert, make sure we do not return zero
        $result=-1;
      } 
      my $loginfo = "";
      if($err && $out && ($err != $out)) {
        $keep_log = 1;
        $loginfo = "\nSee $err and $out for details.";
      } elsif ($err) {
        $keep_log = 1;
        $loginfo = "\nSee $err for details.";
      } elsif ($out) {
        $keep_log = 1;
        $loginfo = "\nSee $out for details.";
      }
      print("HLS $title FAILED.$loginfo\n");
    }
    return ($result);
}

sub log_time($$) {
  my ($label, $time) = @_;
  if ($time_log) {
    printf ($time_log "[time] %s ran in %ds\n", $label, $time);
  }
}

sub save_pkg_section($$$) {
    my ($pkg,$section,$value) = @_;
    # The temporary file should be in the compiler work directory.
    # The work directory has already been created.
    my $file = $g_work_dir.'/value.txt';
    open(VALUE,">$file") or mydie("Can't write to $file: $!");
    binmode(VALUE);
    print VALUE $value;
    close VALUE;
    $pkg->set_file($section,$file)
      or mydie("Can't save value into package file: $acl::Pkg::error\n");
    acl::File::remove_tree($file); # Remove immediatly don't wait for cleanup
}

sub disassemble ($) {
    my $file=$_[0];
    if ( $disassemble ) {
      mysystem_full({'stdout' => ''}, "llvm-dis ".$file ) == 0 or mydie("Cannot disassemble:".$file."\n"); 
    }
}

sub get_acl_board_hw_path {
    my $root = $ENV{"INTELFPGAOCLSDKROOT"};
    return "$root/share/models/bm";  
}

sub remove_named_files {
    foreach my $fname (@_) {
      acl::File::remove_tree( $fname, { verbose => ($verbose>2), dry_run => 0 } )
         or mydie("Cannot remove $fname: $acl::File::error\n");
    }
}

sub unpack_object_files(@) {
    my $work_dir= shift;
    my @list = ();
    my $file;

    acl::File::make_path($work_dir) or mydie($acl::File::error.' While trying to create '.$work_dir);

    foreach $file (@_) {
      my $corename = get_name_core($file);
      my $separator = (isLinuxOS())? '/' : '\\';
      my $fname=$work_dir.$separator.$corename.'.fpga.ll';
      if(get_section_from_object_file($file,$fpga_IR_section,$fname)){
          push @fpga_IR_list, $fname;
        #At least one fpga file, make sure default emulator flag is turned off
        $emulator_flow = 0;
        }
      push @cleanup_list, $fname;

      my $dep_fname=$work_dir.$separator.$corename.'.fpga.d';
      get_section_from_object_file($file,$fpga_dep_section,$dep_fname);
          push @cleanup_list, $dep_fname;

      if (not $RTL_only_flow_modifier) {
            # Regular object file 
            push @list, $file;
          } 
        }
    @object_list=@list;
    if (@fpga_IR_list == 0){
      #No need for project directory, remove it
      push @cleanup_list, $work_dir;
    }
}

# Strips leading directories and removes any extension
sub get_name_core($) {
    my  $base = acl::File::mybasename($_[0]);
    $base =~ s/[^a-z0-9_\.]/_/ig;
    my $suffix = $base;
    $suffix =~ s/.*\.//;
    $base=~ s/\.$suffix//;
    return $base;
}

sub print_debug_log_header($) {
    my $cmd_line = shift;
    open(LOG, ">>$project_log");
    print LOG "*******************************************************\n";
    print LOG " i++ debug log file                                    \n";
    print LOG " This file contains diagnostic information. Any errors \n";
    print LOG " or unexpected behavior encountered when running i++   \n";
    print LOG " should be reported as bugs. Thank you.                \n";
    print LOG "*******************************************************\n";
    print LOG "\n";
    print LOG "Compiler Command: ".$cmd_line."\n";
    print LOG "\n";
    close LOG
}

sub setup_linkstep ($) {
    my $cmd_line = shift;
    # Setup project directory and log file for reminder of compilation
    # We deduce this from the object files and we don't call this if we 
    # know that we are just linking x86

    $g_work_dir = get_project_directory_from_file(@object_list);
    $project_name = (parse_extension($g_work_dir))[0];

    # No turning back, remove anything old
    remove_named_files($g_work_dir,'modelsim.ini');
    remove_named_files($executable) unless ($cosim_linkstep_only);

    acl::File::make_path($g_work_dir) or mydie($acl::File::error.' While trying to create '.$g_work_dir);
    $project_log=${g_work_dir}.'/debug.log';
    $project_log = acl::File::abs_path($project_log);
    print_debug_log_header($cmd_line);
    # Remove immediatly. This is to make sure we don't pick up data from 
    # previos run, not to clean up at the end 

    # Individual file processing, populates fpga_IR_list
    unpack_object_files($g_work_dir, @object_list);

}

sub find_board_spec () {
    my $supported_families = join ', ', keys %family_to_board_map;

    my $board_variant;
    if (exists $family_to_board_map{$dev_family}) {
      $board_variant = $family_to_board_map{$dev_family};
    } elsif (exists $unofficial_family_to_board_map{$dev_family}) {
      # silently support families required by Megacore IPs but not officially supported for i++
      $board_variant = $unofficial_family_to_board_map{$dev_family};
    } else {
      mydie("Unsupported device family. Supported device families are:\n$supported_families\n");
    }
    my $acl_board_hw_path= get_acl_board_hw_path();

    # Make sure the board specification file exists. This is needed by multiple stages of the compile.
    my $board_spec_xml = $acl_board_hw_path."/$board_variant";
    -f $board_spec_xml or mydie("Unsupported device family. Supported device families are:\n$supported_families\n");
    push @llvm_board_option, '-board';
    push @llvm_board_option, $board_spec_xml;
}

# keep the usage help output in alphabetical order within each section!
sub usage() {
    my @family_keys = keys %family_to_board_map;
    my @keys_with_quotes = map { '"'.$_.'"' } @family_keys;
    my $supported_families = join ', ', @keys_with_quotes;
    print <<USAGE;

Usage: i++ [<options>] <input_files> 
Generic flags:
--debug-log Generate the compiler diagnostics log
-h,--help   Display this information
-o <name>   Place the output into <name> and <name>.prj
-v          Verbose mode
--version   Display compiler version information

Flags impacting the compile step (source to object file translation):
-c          Preprocess, parse and generate object files
--component <components>
            Comma-separated list of function names to synthesize to RTL
-D<macro>[=<val>]   
            Define a <macro> with <val> as its value.  If just <macro> is
            given, <val> is taken to be 1
-g          Generate debug information (default)
-g0         Do not generate debug information
-I<dir>     Add directory to the end of the main include path
-march=<arch> 
            Generate code for <arch>, <arch> is one of:
              x86-64, FPGA family, FPGA part code
            FPGA family is one of:
              $supported_families
            or any valid part code from those FPGA families.
--promote-integers  
            Use extra FPGA resources to mimic g++ integer promotion
--quartus-compile 
            Run HDL through a Quartus compilation
--simulator <simulator>
            Specify the simulator to be used for verification.
            Supported simulators are: modelsim (default), none
            If \"none\" is specified, generate RTL for components without testbench

Flags impacting the link step only (object file to binary/RTL translation):
--clock <clock_spec>
            Optimize the RTL for the specified clock frequency or period
--fp-relaxed 
            Relax the order of arithmetic operations
--fpc       Removes intermediate rounding and conversion when possible
-ghdl       Enable full debug visibility and logging of all HDL signals in simulation
-L<dir>     Add directory dir to the list of directories to be searched for -l
            (Only supported on Linux)
-l<library> Search the library named library when linking (Flag is only supported
            on Linux. For Windows, just add .lib files directly to command line)
--x86-only  Only create the executable to run the testbench, but no RTL or 
            cosim support
--fpga-only Create the project directory, all RTL and cosim support, but do 
            not generate the testbench binary 
USAGE

}

sub version($) {
    my $outfile = $_[0];
    print $outfile "Intel(R) HLS Compiler\n";
    print $outfile "Version 17.1.0 Build 590\n";
    print $outfile "Copyright (C) 2017 Intel Corporation\n";
}

sub norm_upper_str($) {
    my $strvar = shift;
    # strip whitespace
    $strvar =~ s/[ \t]//gs;
    # uppercase the string
    $strvar = uc $strvar;
    return $strvar;
}

sub setup_family_and_device() {
    my $cmd = "devinfo \"$dev_device\"";
    chomp(my $devinfo = `$cmd`);
    if($? != 0) {
      mydie("Device information not found.\n$devinfo\n");
    }
    ($dev_family,$dev_part,$dev_speed) = split(",", $devinfo);
    print "Target FPGA part name:   $dev_part\n"   if $verbose;
    print "Target FPGA family name: $dev_family\n" if $verbose;
    print "Target FPGA speed grade: $dev_speed\n"  if $verbose;
}

sub create_reporting_tool {
  my $filelist = shift;
  my $base = shift;
  local $/ = undef;

  acl::Report::copy_files($g_work_dir) or return;

  # Collect information for infoJSON, and print it to the report
  my $mTime = localtime;
  my $ipp_version = "17.1.0 Build 590";

  my $infoJSON = "{\"name\":\"Info\",\"rows\":[\n";
  $infoJSON .= "{\"name\":\"Project Name\",\"data\":[\"".escape_string($base)."\"],\"classes\":[\"info-table\"]},\n";
  $infoJSON .= "{\"name\":\"Target Family, Device\",\"data\":[\"$dev_family, $dev_part\"]},\n";
  $infoJSON .= "{\"name\":\"i++ Version\",\"data\":[\"$ipp_version\"]},\n";
  $infoJSON .= "{\"name\":\"Quartus Version\",\"data\":[\"" .qii_version(). "\"]},\n";
  $infoJSON .= "{\"name\":\"Command\",\"data\":[\"".escape_string($all_ipp_args)."\"]},\n";
  $infoJSON .= "{\"name\":\"Reports Generated At\", \"data\":[\"$mTime\"]}\n";
  $infoJSON .= "]}";

  my $warningsJSON = "{\"rows\":[\n";
  # TODO Add relevant i++ warnings
  $warningsJSON .= "]}";

  # This text is to give user information when --quartus-compile was not ran when calling i++ on how to
  # run quartus compile separately (i.e. not part of the i++ command)
  my $quartusJSON = "{\"quartusFitClockSummary\":{";
  $quartusJSON .= "\"name\":\"Quartus Fit Summary\"";
  $quartusJSON .= ",\"children\":[{";
  $quartusJSON .= "\"name\":\"Run Quartus compile to populate this section. See details for more information.\"";
  $quartusJSON .= ",\"details\":[{\"type\":\"text\", \"text\":\"";
  $quartusJSON .= "This section contains a summary of the area and fmax data generated by compiling the components ";
  $quartusJSON .= "through Quartus.  To generate the data, run a Quartus compile on the project created for this design. ";
  $quartusJSON .= "To run the Quartus compile:\\n";
  $quartusJSON .= "  1) Change to the quartus directory ($g_work_dir/quartus)\\n";
  $quartusJSON .= "  2) quartus_sh --flow compile quartus_compile\\n\"";
  $quartusJSON .= "}]";
  $quartusJSON .= "}]";
  $quartusJSON .= "}}";

  # Create fileJSON
  my @patterns_to_skip = ("\<unknown\>");
  my @dep_files = ();
  for (@dep_files = @fpga_IR_list) { s/\.ll$/\.d/}
  my $fileJSON = acl::Report::get_source_file_info_for_visualizer($filelist, \@patterns_to_skip, \@dep_files, $debug_symbols);
  remove_named_files(@dep_files) unless $save_tmps;

  # create the area_src json file
  acl::Report::parse_to_get_area_src($g_work_dir);
  # List of JSON files to print to report_data.js
  my @json_files = ("area", "area_src", "mav", "lmv", "loops", "summary");
  open (my $report, ">$g_work_dir/reports/lib/report_data.js") or return;

  acl::Report::create_json_file_or_print_to_report($report, "info", $infoJSON, \@json_files, $g_work_dir);
  acl::Report::create_json_file_or_print_to_report($report, "warnings", $warningsJSON, \@json_files, $g_work_dir);
  acl::Report::create_json_file_or_print_to_report($report, "quartus", $quartusJSON, \@json_files, $g_work_dir);

  acl::Report::print_json_files_to_report($report, \@json_files, $g_work_dir);
  
  print $report $fileJSON;
  close($report);

  # create empty verification data file to be filed on simulation run
  open (my $verif_report, ">$g_work_dir/reports/lib/verification_data.js") or return;
  print $verif_report "var verifJSON={};\n";
  close($verif_report);

  if ($pipeline_viewer) {
    acl::Report::create_pipeline_viewer($g_work_dir, "components", $verbose);
  }
}

sub save_and_report{
    my $local_start = time();
    my $filename = shift;
    my $report_dir = "$g_work_dir/reports";
    acl::File::make_path($report_dir) or die;;
    my $pkg = create acl::Pkg(${report_dir}.'/'.get_name_core(${project_name}).'.aoco');

    my $files;
    # Visualization support
    if ( $debug_symbols ) { # Need dwarf file list for this to work
      $files = `file-list \"$g_work_dir/$filename\"`;
      my $index = 0;
      foreach my $file ( split(/\n/, $files) ) {
          save_pkg_section($pkg,'.acl.file.'.$index,$file);
          $pkg->add_file('.acl.source.'. $index,$file)
            or mydie("Can't save source into package file: $acl::Pkg::error\n");
          $index = $index + 1;
      }
      save_pkg_section($pkg,'.acl.nfiles',$index);
    }

    # Get the csr header files, if any
    my @comp_folders = ();
    push @comp_folders, acl::File::simple_glob( $g_work_dir."/components/*" );
    my @csr_h_files = ();
    foreach my $comp_folder (@comp_folders) {
        push @csr_h_files, acl::File::simple_glob( $comp_folder."/*_csr.h" ); 
    }
    my $csr_h_file = join("\n", @csr_h_files);
    $files = $files . $csr_h_file;

    create_reporting_tool($files, $project_name);

    my $json_dir = "$g_work_dir/reports/lib/json";
    my @json_files = ("area", "area_src", "mav", "lmv", "loops", "summary", "info", "warnings", "quartus");
    foreach (@json_files) {
      my $json_file = "$g_work_dir/$_.json";
      if ( -e $json_file ) {
        $pkg->add_file(".acl.$_.json", $json_file)
          or mydie("Can't save $_.json into package file: $acl::Pkg::error\n");
        # There is no acl::File::move, so copy and remove instead.
        acl::File::copy($json_file, "$json_dir/$_.json")
          or warn "Can't copy $_.json to $json_dir\n";
        remove_named_files($json_file);
      }
    }

    # TODO delete these two lines when area.html is no longer created.
    # The file is saved for internal use until the new unified report
    # is stabilized.
    my $area_file_html = $g_work_dir.'/area.html';
    push @cleanup_list, $area_file_html;

    # TODO: delete these two lines when Optimization report is no longer created.
    my $opt_rpt = $g_work_dir.'/opt.rpt';
    acl::File::copy($opt_rpt, "$report_dir/optimization.rpt");
    push @cleanup_list, $opt_rpt;

    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");
    
    log_time ('Create Report', time() - $local_start) if ($time_log);
}

sub clk_get_exp {
    my $var = shift;
    my $exp = $var;
    $exp=~ s/[\.0-9 ]*//;
    return $exp;
}

sub clk_get_mant {
    my $var = shift;
    my $mant = $var;
    my $exp = clk_get_exp($mant);
    $mant =~ s/$exp//g;
    return $mant;
} 

sub clk_get_fmax {
    my $clk = shift;
    my $exp = clk_get_exp($clk);
    my $mant = clk_get_mant($clk);

    my $fmax = undef;

    if ($exp =~ /^GHz/) {
        $fmax = 1000000000 * $mant;
    } elsif ($exp =~ /^MHz/) {
        $fmax = 1000000 * $mant;
    } elsif ($exp =~ /^kHz/) {
        $fmax = 1000 * $mant;
    } elsif ($exp =~ /^Hz/) {
        $fmax = $mant;
    } elsif ($exp =~ /^ms/) {
        $fmax = 1000/$mant;
    } elsif ($exp =~ /^us/) {
        $fmax = 1000000/$mant;
    } elsif ($exp =~ /^ns/) {
        $fmax = 1000000000/$mant;
    } elsif ($exp =~ /^ps/) {
        $fmax = 1000000000000/$mant;
    } elsif ($exp =~ /^s/) {
        $fmax = 1/$mant;
    }
    if (defined $fmax) { 
        $fmax = $fmax/1000000;
    }
    return $fmax;
}

sub query_raw_vsim_version_string() {
    if (!defined $vsim_version_string) {
        $vsim_version_string = `vsim -version`;
    my $error_code = $?;

    if ($error_code != 0) {
        mydie("Error accessing ModelSim.  Please ensure you have a valid ModelSim installation on your path.\n" .
              "       Check your ModelSim installation with \"vsim -version\" \n"); 
    }
    }

    return $vsim_version_string;

}

sub query_vsim_version_string() {
    my $vsim_simple_str = query_raw_vsim_version_string();
    $vsim_simple_str =~ s/^\s+|\s+$//g;
    return $vsim_simple_str;
}

sub query_vsim_arch() {
    if (!defined $cosim_64bit) {
      my $vsim_version_str = query_raw_vsim_version_string();
    $cosim_64bit = ($vsim_version_str =~ /64 vsim/);
    }

    return $cosim_64bit;
}

sub quartus_version_str() {
  if (!defined $g_quartus_version_str) {
    $g_quartus_version_str = `quartus_sh -v`;
    my $error_code = $?;

    if ($error_code != 0) {
        mydie("Error accessing Quartus. Please ensure you have a valid Quartus installation on your path.\n");
    }
  }

  return $g_quartus_version_str;
}

sub qii_is_pro() {
  return (quartus_version_str() =~ /Pro Edition/);
}

sub qii_version() {
  my $q_version_str = quartus_version_str();
  $q_version_str =~ /Version (.* Build \d*)/;
  my $qii_version = $1;
  return $qii_version;
}

sub parse_args {
    my $stdarg="-std=";
    my @user_parseflags = ();
    my @user_linkflags =();
    while ( $#ARGV >= 0 ) {
      my $arg = shift @ARGV;
      if ( ($arg eq '-h') or ($arg eq '--help') ) { usage(); exit 0; }
      elsif ($arg eq '--list-deps') { print join("\n",values %INC),"\n"; exit 0; }
      elsif ($arg=~/$stdarg/i) { mydie('The -std option is not supported.'); }
      elsif ( ($arg eq '--version') or ($arg eq '-V') ) { version(\*STDOUT); exit 0; }
      elsif ( ($arg eq '-v') ) { $verbose += 1; if ($verbose > 1) {$prog = "#$prog";} }
      elsif ( ($arg eq '-g') ) { 
          $user_required_debug_symbol = 1;
          $debug_symbols = 1;
      }
      elsif ( ($arg eq '-g0') ) { $debug_symbols = 0;}
      elsif ( ($arg eq '-o') ) {
          # Absorb -o argument, and don't pass it down to Clang
          ($#ARGV >= 0 && $ARGV[0] !~ m/^-./) or mydie("Option $arg requires a name argument.");
          $project_name = shift @ARGV;
      }
      elsif ( $arg =~ /^-o(.+)/ ) {
          $project_name = $1;
      }
      elsif ( ($arg eq '--component') ) {
          ($#ARGV >= 0 && $ARGV[0] !~ m/^-./) or mydie('Option --component requires a function name');
          push @component_names, shift @ARGV;
      }
      elsif ( $arg =~ /^-march=(.*)/ ) {
        $march_set = 1;
        my $arch = $1;
        if      ($arch eq 'x86-64') {
          $emulator_flow = 1;
        } else {
          $simulator_flow = 1;
          $dev_device = $arch;
        }
      }
      elsif ($arg eq '--cosim' ) {
          $RTL_only_flow_modifier = 0;
      }
      elsif ($arg eq '--x86-only' ) {
          $x86_linkstep_only = 1;
          $cosim_linkstep_only = 0;
      }
      elsif ($arg eq '--fpga-only' ) {
          $cosim_linkstep_only = 1;
          $x86_linkstep_only = 0;
      }
      elsif ($arg eq '-ghdl') {
          $RTL_only_flow_modifier = 0;
          $cosim_debug = 1;
      }
      elsif ($arg eq '--simulator') {
          $#ARGV >= 0 or mydie('Option --simulator requires an argument');
          $cosim_simulator = norm_upper_str(shift @ARGV);
      }
      elsif ($arg eq '--cosim-log-call-count') {
          $cosim_log_call_count = 1;
      }
      elsif ( ($arg eq '--regtest_mode') ) {
          $time_log = "time.out";
          $keep_log = 1;
          $save_tmps = 1;
          push @additional_llc_args, "-dump-hld-area-debug-files";
      }
      elsif ( ($arg eq '--clang-arg') ) {
          $#ARGV >= 0 or mydie('Option --clang-arg requires an argument');
          # Just push onto args list
          push @user_parseflags, shift @ARGV;
      }
      elsif ( ($arg eq '--debug-log') ) {
        $keep_log = 1;
      }
      elsif ( ($arg eq '--opt-arg') ) {
          $#ARGV >= 0 or mydie('Option --opt-arg requires an argument');
          push @additional_opt_args, shift @ARGV;
      }
      elsif ( ($arg eq '--llc-arg') ) {
          $#ARGV >= 0 or mydie('Option --llc-arg requires an argument');
          push @additional_llc_args, shift @ARGV;
      }
      elsif ( ($arg eq '--optllc-arg') ) {
          $#ARGV >= 0 or mydie('Option --optllc-arg requires an argument');
          my $optllc_arg = (shift @ARGV);
          push @additional_opt_args, $optllc_arg;
          push @additional_llc_args, $optllc_arg;
      }
      elsif ( ($arg eq '--sysinteg-arg') ) {
          $#ARGV >= 0 or mydie('Option --sysinteg-arg requires an argument');
          push @additional_sysinteg_args, shift @ARGV;
      }
      elsif ( ($arg eq '-c') ) {
          $object_only_flow_modifier = 1;
      }
      elsif ( ($arg eq '--dis') ) {
          $disassemble = 1;
      }
      elsif ($arg eq '--dot') {
        $dotfiles = 1;
      }
      elsif ($arg eq '--pipeline-viewer') {
        $dotfiles = 1;
        $pipeline_viewer = 1;
      }
      elsif ($arg eq '--save-temps') {
        $save_tmps = 1;
      }
      elsif ($arg eq '-save-temps') {
        mydie('unsupported option \'-save-temps\'');
      }
      elsif ( ($arg eq '--clock') ) {
          my $clk_option = (shift @ARGV);
          $qii_fmax_constraint = clk_get_fmax($clk_option);
          if (!defined $qii_fmax_constraint) {
              mydie("i++: bad value ($clk_option) for --clock argument\n");
          }
          push @additional_opt_args, '-scheduler-fmax='.$qii_fmax_constraint;
          push @additional_llc_args, '-scheduler-fmax='.$qii_fmax_constraint;
      }
      elsif ( ($arg eq '--fp-relaxed') ) {
          push @additional_opt_args, "-fp-relaxed=true";
      }
      elsif ( ($arg eq '--fpc') ) {
          push @additional_opt_args, "-fpc=true";
      }
      elsif ( ($arg eq '--promote-integers') ) {
          push @user_parseflags, "-fhls-int-promotion";
      }
      # Soft IP C generation flow
      elsif ($arg eq '--soft-ip-c') {
          $soft_ip_c_flow_modifier = 1;
          $simulator_flow = 1;
          $disassemble = 1;
      }
      # Soft IP C generation flow for x86
      elsif ($arg eq '--soft-ip-c-x86') {
          $soft_ip_c_flow_modifier = 1;
          $simulator_flow = 1;
          $target_x86 = 1;
          $opt_passes = "-inline -inline-threshold=10000000 -dce -stripnk -cleanup-soft-ip";
          $disassemble = 1;
      }
      elsif ($arg eq '--quartus-compile') {
          $qii_flow = 1;
      }
      elsif ($arg eq '--quartus-no-vpins') {
          $qii_vpins = 0;
      }
      elsif ($arg eq '--quartus-dont-register-ios') {
          $qii_io_regs = 0;
      }
      elsif ($arg eq '--quartus-aggressive-pack-dsps') {
          $qii_dsp_packed = 1;
      }
      elsif ($arg eq "--quartus-seed") {
          $qii_seed = shift @ARGV;
      }
      elsif ($arg eq '--standalone') {
        # Our tools use this flag to indicate that the package should not check for existance of ACDS
        # Currently unused by i++ but we don't want to pass this flag to Clang so we gobble it up here
      }
      elsif ($arg eq '--time') {
        if($#ARGV >= 0 && $ARGV[0] !~ m/^-./) {
          $time_log = shift(@ARGV);
        }
        else {
          $time_log = "-"; # Default to stdout.
        }
      }
      elsif ($arg =~ /^-[lL]/ or
             $arg =~ /^-Wl/) {
          isLinuxOS() or mydie("\"$arg\" not supported on Windows. List the libraries on the command line instead.");
          push @user_linkflags, $arg;
      }
      elsif ($arg eq '-I') { # -Iinc syntax falls through to default below (even if first letter of inc id ' '
          ($#ARGV >= 0 && $ARGV[0] !~ m/^-./) or mydie("Option $arg requires a name argument.");
          push  @user_parseflags, $arg.(shift @ARGV);
      }
      elsif ( $arg =~ m/\.c$|\.cc$|\.cp$|\.cxx$|\.cpp$|\.CPP$|\.c\+\+$|\.C$/ ) {
          push @source_list, $arg;
      }
      elsif ( $arg =~ m/\Q$default_object_extension\E$/ ) {
          push @object_list, $arg;
      } 
      elsif ( $arg =~ m/\.lib$/ && isWindowsOS()) {
          push @user_linkflags, $arg;
      }
      elsif ( ($arg eq '-E')  or ($arg =~ /^-M/ ) ){ #preprocess only;
          $preprocess_only= 1;
          $object_only_flow_modifier= 1;
          push @user_parseflags, $arg;
      } else {
          push @user_parseflags, $arg;
      }
    }

    # Default to x86-64
    if ( not $emulator_flow and not $simulator_flow and not $x86_linkstep_only) {
      $emulator_flow = 1;
    }

    # if $debug_symbols is set and we're running on
    # a Windows OS, disable debug symbols silently here
    # since the default is to generate debug_symbols.
    if ($debug_symbols && $emulator_flow && isWindowsOS()) {
      $debug_symbols = 0;
      # if the user explicitly requests debug symbols and we're running on a Windows OS with -march=x86-64
      # dont't enable debug symbols.
      if ($user_required_debug_symbol){
        print "$prog: Debug symbols are not supported on Windows for x86, ignoring -g.\n";
      } 
    }

    if (@component_names) {
      push @user_parseflags, "-Xclang";
      push @user_parseflags, "-soft-ip-c-func-name=".join(',',@component_names);
    }

    # All arguments in, make sure we have at least one file
    (@source_list + @object_list) > 0 or mydie('No input files');
    if ($debug_symbols) {
      push @user_parseflags, '-g';
      push @additional_llc_args, '-dbg-info-enabled';
    }

    if (!$emulator_flow){
        if ($cosim_simulator eq "NONE") {
            $RTL_only_flow_modifier = 1;
        } elsif ($cosim_simulator eq "MODELSIM") {
            query_vsim_arch();
        } else {
            mydie("Unrecognized simulator $cosim_simulator\n");
        }
    }

    if ( $emulator_flow && $cosim_simulator eq "NONE") {
      mydie("i++: The --simulator none flag is valid only with FPGA architectures\n");
    }

    open_time_log_file();

    # make sure that the device and family variables are set to the correct
    # values based on the user inputs and the flow
    setup_family_and_device();

    # Make sure that the qii compile flow is only used with the altera compile flow
    if ($qii_flow and not $simulator_flow) {
        mydie("The --quartus-compile argument can only be used with FPGA architectures\n");
    }
    # Check qii flow args
    if ((not $qii_flow) and $qii_dsp_packed) {
        mydie("The --quartus-aggressive-pack-dsps argument must be used with the --quartus-compile argument\n");
    }
    if ($qii_dsp_packed and not ($dev_family eq "Arria 10")) {
        mydie("The --quartus-aggressive-pack-dsps argument is only applicable to the Arria 10 device family\n");
    }

    if ($dotfiles) {
      push @additional_opt_args, '--dump-dot';
      push @additional_llc_args, '--dump-dot'; 
      push @additional_sysinteg_args, '--dump-dot';
    }

    # caching is disabled for LSUs in HLS components for now
    # enabling caches is tracked by case:314272
    push @additional_opt_args, '-nocaching';
    push @additional_opt_args, '-noprefetching';

    $orig_dir = acl::File::abs_path('.');

    # Check legality related to --x86-only and --fpga-only
    if ($object_only_flow_modifier) {
      if ($x86_linkstep_only) {
        print "Warning:--x86-only has no effect\n";
      }
      if ($cosim_linkstep_only) {
        print "Warnign:--fpga-only has no effect\n";
      }
    }
    if ($march_set &&  $#source_list<0) {
      print "Warning:-march has no effect. Using settings from -c compile\n";
    }
    if ($cosim_linkstep_only && $project_name) {
      print "Warning:-o has no effect. Project directory name set during -c compile\n";
    }
    if ($x86_linkstep_only && $cosim_linkstep_only) {
      mydie("Command line can only contain one of --x86_linkstep_only --fpga_linkstep_only\n");
    }
    
    # Sanity check and generate the project and executable name
    # Defaults follow g++ convention on the respective platform:
    #   Windows Default: a.exe / a.prj
    #   Linux Default: a.out / a.prj
    if ( $project_name ) {
      if ( $#source_list > 0 && $object_only_flow_modifier) {
        mydie("Cannot specify -o with -c and multiple source files\n");
      }
      if ( !$object_only_flow_modifier && $project_name =~ m/\Q$default_object_extension\E$/) {
        mydie("'-o $project_name'. Result files with extension $default_object_extension only allowed together with -c\n");
      }
      if (isLinuxOS()) {
        $executable = $project_name;
      } else  {
        my ($basename, $extension) = parse_extension($project_name);
        if ($extension eq '.exe') {
          $executable = $project_name;
        } else {
          $executable = $project_name.'.exe';
    }
      }
    } else {
      $project_name = 'a';
      $executable = ${project_name}.(isWindowsOS() ? '.exe' : '.out');
    }

    # Consolidate some flags
    push (@parseflags, @user_parseflags);
    push (@parseflags,"-I" . $ENV{'INTELFPGAOCLSDKROOT'} . "/include");

    my $emulator_arch=acl::Env::get_arch();
    my $host_lib_path = acl::File::abs_path( acl::Env::sdk_root().'/host/'.${emulator_arch}.'/lib');
    push (@linkflags, @user_linkflags);
    if (isLinuxOS()) {
      push (@linkflags, '-lstdc++');
      push (@linkflags, '-lm');
      push (@linkflags, '-L'.$host_lib_path);
    }
}

sub fpga_parse ($$$){
    my $source_file= shift;
    my $objfile = shift;
    my $work_dir = shift;
    print "Analyzing $source_file for hardware generation\n" if $verbose;

    # OK, no turning back remove the old result file, so no one thinks we 
    # succedded. Can't be defered since we only clean it up IF we don't do -c
    if ($preprocess_only || !$object_only_flow_modifier) { 
      push @cleanup_list, $objfile; 
    };

    my $outputfile=$work_dir.'/fpga.ll';
    (my $dep_file=$outputfile) =~ s/\.ll/\.d/;
    my @clang_dependency_args = ("-MMD");

    my @clang_std_opts2 = qw(-S -x hls -emit-llvm -Wuninitialized -fno-exceptions);
    if ( $target_x86 == 0 ) {
      if (isLinuxOS()) {
        push (@clang_std_opts2, qw(-ccc-host-triple fpga64-unknown-linux));
      } elsif (isWindowsOS()) {
        push (@clang_std_opts2, qw(-ccc-host-triple fpga64-unknown-win32));
      }
    }

    @cmd_list = (
      $clang_exe,
      ($verbose>2)?'-v':'',
      @clang_std_opts2,
      "-D__INTELFPGA_TYPE__=$macro_type_string",
      "-DHLS_SYNTHESIS",
      @parseflags,
      $source_file,
      @clang_dependency_args,
      $preprocess_only ? '':('-o',$outputfile)
    );

    $return_status = mysystem_full( {'title' => 'FPGA Parse'}, @cmd_list);
    if ($return_status) {
        push @cleanup_list, $objfile; #Object file created
        mydie();
    }
    if (!$preprocess_only) {
      my $separator = (isLinuxOS())? '/' : '\\';
      my $prj_name_tmpfile = $work_dir.$separator.'prj_name.txt';
      my $prj_name = acl::File::mydirname($project_name).(parse_extension(acl::File::mybasename($project_name)))[0];

      # add section to object file unless we are going straight to linkstep
      if($object_only_flow_modifier){
      open FILE, ">$prj_name_tmpfile"; binmode FILE; print FILE ${prj_name}.".prj"; close FILE;
      add_projectname_to_object_file($objfile,$prj_name_section,$prj_name_tmpfile,$outputfile);
      push @cleanup_list, $prj_name_tmpfile;

      add_section_to_object_file($objfile,$fpga_IR_section,$outputfile);
        add_section_to_object_file($objfile,$fpga_dep_section,$dep_file);
      } else {
        $g_work_dir = $prj_name.'.prj';
        push @fpga_IR_list, $outputfile;
        # push @???, $dep_file;
        # FB:491973
      }
        push @cleanup_list, $outputfile;
        push @cleanup_list, $dep_file;
    }
}

sub testbench_compile ($$$) {
    my $source_file= shift;
    my $object_file = shift;
    my $work_dir = shift;
    print "Analyzing $source_file for testbench generation\n" if $verbose;

    my @clang_std_opts = qw(-S -emit-llvm  -x hls -O0 -Wuninitialized);

    my @macro_options;
    @macro_options= qw(-DHLS_X86);

    #On Windows, do not use -g
    my @parseflags_nog;
    if (isWindowsOS()){
      @parseflags_nog = grep { $_ ne '-g' } @parseflags;
      if ($user_required_debug_symbol){
        print "$prog: Debug symbols are not supported on Windows for testbench parse, ignoring -g.\n";
      }
    } else {
      @parseflags_nog = @parseflags;
    }
    
    my $parsed_file=$work_dir.'/tb.ll';
    @cmd_list = (
      $clang_exe,
      ($verbose>2)?'-v':'',
      @clang_std_opts,
      "-D__INTELFPGA_TYPE__=$macro_type_string",
      @parseflags_nog,
      @macro_options,
      $source_file,
      $preprocess_only ? '':('-o',$parsed_file)
      );

    $return_status = mysystem_full( {'title' => 'Testbench parse'}, @cmd_list);
    if ($return_status != 0) {
        push @cleanup_list, $object_file; #Object file created
      mydie();
    }

    if ($preprocess_only) {
      return;
    }

    push @cleanup_list, $parsed_file;
    print "Creating x86-64 testbench \n" if $verbose;

    my $resfile=$work_dir.'/tb.bc';
    my @flow_options= qw(-replacecomponentshlssim);
    my $verification_path = acl::File::mybasename((parse_extension(${project_name}))[0]).".prj";

    my $simscript = get_sim_script_dir() . '/msim_run.tcl';

    my @cosim_verification_opts = ("-verificationpath", "$verification_path/$cosim_work_dir", "-verificationscript", "$simscript");
    @cmd_list = (
      $opt_exe,  
      @flow_options,
      @cosim_verification_opts,
      @additional_opt_args,
      @llvm_board_option,
      '-o', $resfile,
      $parsed_file );
    mysystem_full( {'title' => 'Testbench component wrapper generation'}, @cmd_list) == 0 or mydie();
    disassemble($resfile);

    push @cleanup_list, $resfile;

    my @clang_std_opts2;
    if (isLinuxOS()) {
      @clang_std_opts2 = qw(-B/usr/bin -O0);
    } elsif (isWindowsOS()) {
      @clang_std_opts2 = qw(-O0);
    }

    my @cosim_libs;
    push @cosim_libs, '-lhls_cosim';

    if (isLinuxOS()) {
      @cmd_list = (
        $clang_exe,'-c',
        ($verbose>2)?'-v':'',
        $resfile,
        '-o', $object_file);
    } elsif (isWindowsOS()) {
      @cmd_list = (
        $clang_exe, '-c',
        ($verbose>2)?'-v':'',
        @clang_std_opts2,
        $resfile,
        "-D__INTELFPGA_TYPE__=$macro_type_string",
        "-DHLS_SYNTHESIS",
        '-o', $object_file);

    }
    mysystem_full({'title' => 'Clang (Generating testbench object file)'}, @cmd_list ) == 0 or mydie();

    if (!$object_only_flow_modifier) {
      push @cleanup_list, $resfile;
      push @object_list, $object_file;
    }
}

sub emulator_compile ($$) {
    my $source_file= shift;
    my $object_file = shift;
    print "Analyzing $source_file\n" if $verbose;
    @cmd_list = (
      $clang_exe,
      ($verbose>2)?'-v':'',
      qw(-x hls -O0 -Wuninitialized -c),
      '-DHLS_X86',
      "-D__INTELFPGA_TYPE__=$macro_type_string",
      $source_file,
      @parseflags,
      $preprocess_only ? '':('-o',$object_file)
    );

    mysystem_full(
      {'title' => 'x86-64 compile'}, @cmd_list) == 0 or mydie();

    push @object_list, $object_file;
    if (!$object_only_flow_modifier) { push @cleanup_list, $object_file; };
}

sub generate_fpga(@){
    my @IR_list=@_;
    print "Optimizing component(s) and generating Verilog files\n" if $verbose;

    my $all_sources = link_IR("fpga_merged", @{IR_list});
    push @cleanup_list, $all_sources;
    my $linked_bc=$g_work_dir.'/fpga.linked.bc';

    # Link with standard library.
    my $early_bc = acl::File::abs_path( acl::Env::sdk_root().'/share/lib/acl/acl_early.bc');
    @cmd_list = (
      $link_exe,
      $all_sources,
      $early_bc,
      '-o',
      $linked_bc );
    
    mysystem_full( {'title' => 'Early IP Link'}, @cmd_list) == 0 or mydie();
    
    disassemble($linked_bc);
    
    # llc produces visualization data in the current directory
    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");
    
    my $kwgid='fpga.opt.bc';
    my @flow_options = qw(-HLS);
    if ( $soft_ip_c_flow_modifier ) { push(@flow_options, qw(-SIPC)); }
    push(@flow_options, qw(--grif --soft-elementary-math=false --fas=false));
    my @cmd_list = (
      $opt_exe,
      @flow_options,
      split( /\s+/,$opt_passes),
      @llvm_board_option,
      @additional_opt_args,
      'fpga.linked.bc',
      '-o', $kwgid );
    mysystem_full( {'title' => 'Main Optimizer'}, @cmd_list ) == 0 or mydie();
    disassemble($kwgid);
    if ( $soft_ip_c_flow_modifier ) { myexit('Soft IP'); }

    # Lower instructions to IP library function calls
    my $lowered='fpga.lowered.bc';
    @flow_options = qw(-HLS -insert-ip-library-calls);
    push(@flow_options, qw(--grif --soft-elementary-math=false --fas=false)); 
    @cmd_list = (
        $opt_exe,
        @flow_options,
        @additional_opt_args,
        $kwgid,
        '-o', $lowered);
    mysystem_full( {'title' => 'Lower intrinsics to IP calls'}, @cmd_list ) == 0 or mydie();

    # Link with the soft IP library 
    my $linked='fpga.linked2.bc';
    my $late_bc = acl::File::abs_path( acl::Env::sdk_root().'/share/lib/acl/acl_late.bc');
    @cmd_list = (
      $link_exe,
      $lowered,
      $late_bc,
      '-o', $linked );
    mysystem_full( {'title' => 'Late IP library'}, @cmd_list)  == 0 or mydie();

    # Inline IP calls, simplify and clean up
    my $final = get_name_core(${project_name}).'.bc';
    @cmd_list = (
      $opt_exe,
      qw(-HLS -always-inline -add-inline-tag -instcombine -adjust-sizes -dce -stripnk -rename-basic-blocks),
      @llvm_board_option,
      @additional_opt_args,
      $linked,
      '-o', $final);
    mysystem_full( {'title' => 'Inline and clean up'}, @cmd_list) == 0 or mydie();
    disassemble($final);
    push @cleanup_list, $g_work_dir."/$final";

    my $llc_option_macro = ' -march=griffin ';
    my @llc_option_macro_array = split(' ', $llc_option_macro);
    push(@additional_llc_args, qw(--grif));

    # DSPBA backend needs to know the device that we're targeting
      push(@additional_llc_args, qw(--device));
      push(@additional_llc_args, qq($dev_part) );

      # DSPBA backend needs to know the device family - Bugz:309237 tracks extraction of this info from the part number in DSPBA
      # Device is defined by this point - even if it was set to the default.
      # Query Quartus to get the device family`
      push(@additional_llc_args, qw(--family));
      push(@additional_llc_args, "\"".$dev_family."\"" );

      # DSPBA backend needs to know the device speed grade - Bugz:309237 tracks extraction of this info from the part number in DSPBA
      # The device is now defined, even if we've chosen the default automatically.
      # Query Quartus to get the device speed grade.
      push(@additional_llc_args, qw(--speed_grade));
      push(@additional_llc_args, qq($dev_speed) );

    @cmd_list = (
        $llc_exe,
        @llc_option_macro_array,
        qw(-HLS),
        qw(--board hls.xml),
        @additional_llc_args,
        $final,
        '-o',
        get_name_core($project_name).'.v' );
    mysystem_full({'title' => 'Verilog code generation, llc'}, @cmd_list) == 0 or mydie();

    my $xml_file = get_name_core(${project_name}).'.bc.xml';
    mysystem_full(
      {'title' => 'System Integration'},
      ($sysinteg_exe, @additional_sysinteg_args,'--hls', 'hls.xml', $xml_file )) == 0 or mydie();

    my @components = get_generated_components();
    my $ipgen_result = create_qsys_components(@components);
    mydie("Failed to generate Qsys files\n") if ($ipgen_result);

    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");

    #Cleanup everything but final bc
    push @cleanup_list, acl::File::simple_glob( $g_work_dir."/*.*.bc" );
    push @cleanup_list, $g_work_dir."/$xml_file";
    push @cleanup_list, $g_work_dir.'/hls.xml';
    push @cleanup_list, $g_work_dir.'/'.get_name_core($project_name).'.v';
    push @cleanup_list, acl::File::simple_glob( $g_work_dir."/*.attrib" );
    push @cleanup_list, $g_work_dir.'/interfacedesc.txt';
    push @cleanup_list, $g_work_dir.'/compiler_metrics.out';

    save_and_report(${final});
}

sub link_IR (@) {
    my ($basename,@list) = @_;
    my $result_file = shift @list;
    my $indexnum = 0;
    foreach (@list) {
        # Just add one file at the time since llvm-link has some issues
        # with unifying types otherwise. Introduces small overhead if 3
        # source files or more
        my $next_res = ${g_work_dir}.'/'.${basename}.${indexnum}++.'.bc';

        @cmd_list = (
            $link_exe,
            $result_file,
            $_,
            '-o',$next_res );

        mysystem_full( {'title' => 'Link IR'}, @cmd_list) == 0 or mydie();
        push @cleanup_list, $next_res;

        $result_file = ${next_res};
    }
    if ($result_file =~ /\.bc$/) { disassemble($result_file); }
    return $result_file;
}

sub link_x86 ($$) {
    my $output_name = shift ;
    my $emulator_flow = shift;
    print "Linking x86 objects\n" if $verbose;

    acl::File::make_path(acl::File::mydirname($output_name)) or mydie("Can't create simulation directory ".acl::File::mydirname($output_name).": $!");

    if (isLinuxOS()) {
      if ($emulator_flow){
        push @linkflags, '-lhls_emul';
      } else {
        push @linkflags, '-lhls_cosim';
      }
      push @linkflags, '-lhls_fixed_point_math_x86';
      push @linkflags, '-laltera_mpir';
      push @linkflags, '-laltera_mpfr';
    
    @cmd_list = (
      $clang_exe,
      ($verbose>2)?'-v':'',
      @object_list,
      '-o',
      $executable,
      @linkflags,
      );

    } else {
      check_link_exe_existance();
      @cmd_list = (
        $mslink_exe,
        @object_list,
        @linkflags,
        '-nologo',
        '-defaultlib:libcpmt',
          '-force:multiple',
          '-ignore:4006',
          '-ignore:4088',
        '-out:'.$executable);

      push @cmd_list, get_hlsvbase_path();
      push @cmd_list, get_msvcrt_path();
      push @cmd_list, get_hlsfixed_point_math_x86_path();
      push @cmd_list, get_mpir_path();
      push @cmd_list, get_mpfr_path();

      if ($emulator_flow){
        push @cmd_list, get_hlsemul_path();
      } else {
        push @cmd_list, get_hlscosim_path();
    }
    }
      mysystem_full( {'title' => 'Link x86-64'}, @cmd_list) == 0 or mydie();
    
    return;
}

sub get_generated_components() {
  # read the comma-separated list of components from a file
  my $project_bc_xml_filename = get_name_core(${project_name}).'.bc.xml';
  my $BC_XML_FILE;
  open (BC_XML_FILE, "<${project_bc_xml_filename}") or mydie "Couldn't open ${project_bc_xml_filename} for read!\n";
  my @dut_array;
  while(my $var =<BC_XML_FILE>) {
    if ($var =~ /<KERNEL name="(.*)" filename/) {
        push(@dut_array,$1); 
    }
  }
  close BC_XML_FILE;
  return @dut_array;
}

sub hls_sim_generate_verilog(@) {
    my $projdir = acl::File::mybasename($g_work_dir);
    print "Generating cosimulation support\n" if $verbose;
    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");
    my @dut_array = get_generated_components();
    # finally, recreate the comma-separated string from the array with unique elements
    my $DUT_LIST  = join(',',@dut_array);
    print "Generating simulation files for components: $DUT_LIST\n" if $verbose;
    my $SEARCH_PATH = acl::Env::sdk_root()."/ip/,.,../components/**/*,\$"; # no space between paths!

    # Setup file path names

    # Because the qsys-script tcl cannot accept arguments, 
    # pass them in using the --cmd option, which runs a tcl cmd
    #
    # Set default value of $count_log
    my $count_log = ".";

    if ($cosim_log_call_count) {
      $count_log = "sim_component_call_count.log";
    }
    my $set_pro = qii_is_pro() ?  1 : 0;
    my $num_reset_cycles = 4;
    my $init_var_tcl_cmd = "set quartus_pro $set_pro; set num_reset_cycles $num_reset_cycles; set sim_qsys $tbname; set component_list $DUT_LIST; set component_call_count_filename $count_log";

    # Create the simulation directory and enter it
    my $sim_dir_abs_path = acl::File::abs_path("./$cosim_work_dir");
    print "HLS simulation directory: $sim_dir_abs_path.\n" if $verbose;
    acl::File::make_path($cosim_work_dir) or mydie("Can't create simulation directory $sim_dir_abs_path: $!");
    chdir $cosim_work_dir or mydie("Can't change into dir $cosim_work_dir: $!\n");

    my $gen_qsys_tcl = acl::Env::sdk_root()."/share/lib/tcl/hls_sim_generate_qsys.tcl";

    # Run hls_sim_generate_qsys.tcl to generate the .qsys file for the simulation system 
    my $pro_string = "";
    if (qii_is_pro()) { $pro_string = "--quartus-project=none"; }
    mysystem_full(
      {'stdout' => $project_log,'stderr' => $project_log, 'title' => 'Generate testbench QSYS system'},
      'qsys-script',
      $pro_string,
      '--search-path='.$SEARCH_PATH,
      '--script='.$gen_qsys_tcl,
      '--cmd='.$init_var_tcl_cmd)  == 0 or mydie();

    # Generate the verilog for the simulation system
    @cmd_list = ('qsys-generate',
      '--search-path='.$SEARCH_PATH,
      '--simulation=VERILOG',
      '--family='.$dev_family,
      '--part='.$dev_part,
      $tbname.".qsys");
    mysystem_full(
      {'stdout' => $project_log, 'stderr' => $project_log, 'title' => 'Generate testbench Verilog from QSYS system'}, 
      @cmd_list)  == 0 or mydie();

    # Generate scripts that the user can run to perform the actual simulation.
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");
    generate_simulation_scripts();
}


# This module creates a file:
# Moved everything into one file to deal with run time parameters, i.e. execution directory vs scripts placement.
#Previous do scripts are rewritten to strings that gets put into the run script
#Also perl driver in project directory is gone.
#  - compile_do      (the string run by the compilation phase, in the output dir)
#  - simulate_do     (the string run by the simulation phase, in the output dir)
#  - <source>        (the executable top-level simulation script, in the top-level dir)
sub generate_simulation_scripts() {
    # Working directories
    my $projdir = acl::File::mybasename($g_work_dir);
    my $qsyssimdir = get_qsys_sim_dir();
    my $simscriptdir = get_sim_script_dir();
    my $cosimdir = "$g_work_dir/$cosim_work_dir";
    # Library names
    my $cosimlib = query_vsim_arch() ? 'hls_cosim_msim' : 'hls_cosim_msim32';
    # Script filenames
    my $fname_compilescript = $simscriptdir.'/msim_compile.tcl';
    my $fname_runscript = $simscriptdir.'/msim_run.tcl';
    my $fname_msimsetup = $simscriptdir.'/msim_setup.tcl';
    my $fname_svlib = $ENV{'INTELFPGAOCLSDKROOT'} . (isLinuxOS() ? "/host/linux64/lib/lib${cosimlib}" : "/windows64/bin/${cosimlib}");
    my $fname_exe_com_script = isLinuxOS() ? 'compile.sh' : 'compile.cmd';

    # Modify the msim_setup script
    post_process_msim_file("$cosimdir/$fname_msimsetup", "$simscriptdir");
    
    # Generate the modelsim compilation script
    my $COMPILE_SCRIPT_FILE;
    open(COMPILE_SCRIPT_FILE, ">", "$cosimdir/$fname_compilescript") or mydie "Couldn't open $cosimdir/$fname_compilescript for write!\n";
    print COMPILE_SCRIPT_FILE "onerror {abort all; exit -code 1;}\n";
    print COMPILE_SCRIPT_FILE "set VSIM_VERSION_STR \"", query_vsim_version_string(), "\"\n";
    print COMPILE_SCRIPT_FILE "set QSYS_SIMDIR $qsyssimdir\n";
    print COMPILE_SCRIPT_FILE "source $fname_msimsetup\n";
    print COMPILE_SCRIPT_FILE "set ELAB_OPTIONS \"+nowarnTFMPC";
    if (isWindowsOS()) {
        print COMPILE_SCRIPT_FILE " -nodpiexports";
    }
    print COMPILE_SCRIPT_FILE ($cosim_debug ? " -voptargs=+acc\"\n"
                                            : "\"\n");
    print COMPILE_SCRIPT_FILE "dev_com\n";
    print COMPILE_SCRIPT_FILE "com\n";
    print COMPILE_SCRIPT_FILE "elab\n";
    print COMPILE_SCRIPT_FILE "exit -code 0\n";
    close(COMPILE_SCRIPT_FILE);

    # Generate the run script
    my $RUN_SCRIPT_FILE;
    open(RUN_SCRIPT_FILE, ">", "$cosimdir/$fname_runscript") or mydie "Couldn't open $cosimdir/$fname_runscript for write!\n";
    print RUN_SCRIPT_FILE "onerror {abort all; puts stderr \"The simulation process encountered an error and has aborted.\"; exit -code 1;}\n";
    print RUN_SCRIPT_FILE "set VSIM_VERSION_STR \"", query_vsim_version_string(),"\"\n";
    print RUN_SCRIPT_FILE "set QSYS_SIMDIR $qsyssimdir\n";
    print RUN_SCRIPT_FILE "source $fname_msimsetup\n";
    print RUN_SCRIPT_FILE "# Suppress warnings from the std arithmetic libraries\n";
    print RUN_SCRIPT_FILE "set StdArithNoWarnings 1\n";
    print RUN_SCRIPT_FILE "set ELAB_OPTIONS \"+nowarnTFMPC -dpioutoftheblue 1 -sv_lib \\\"$fname_svlib\\\"";
    if (isWindowsOS()) {
        print RUN_SCRIPT_FILE " -nodpiexports";
    }
    print RUN_SCRIPT_FILE ($cosim_debug ? " -voptargs=+acc\"\n"
                                        : "\"\n");
    print RUN_SCRIPT_FILE "elab\n";
    print RUN_SCRIPT_FILE "onfinish {stop}\n";
    print RUN_SCRIPT_FILE "log -r *\n" if $cosim_debug;
    print RUN_SCRIPT_FILE "run -all\n";
    print RUN_SCRIPT_FILE "set failed [expr [coverage attribute -name TESTSTATUS -concise] > 1]\n";
    print RUN_SCRIPT_FILE "if {\${failed} != 0} { puts stderr \"The simulation process encountered an error and has been terminated.\"; }\n";
    print RUN_SCRIPT_FILE "exit -code \${failed}\n";
    close(RUN_SCRIPT_FILE);


    # Generate a script that we'll call to compile the design
    my $EXE_COM_FILE;
    open(EXE_COM_FILE, '>', "$cosimdir/$fname_exe_com_script") or die "Could not open file '$cosimdir/$fname_exe_com_script' $!";
    if (isLinuxOS()) {
      print EXE_COM_FILE "#!/bin/sh\n";
      print EXE_COM_FILE "\n";
      print EXE_COM_FILE "# Identify the directory to run from\n";
      print EXE_COM_FILE "rundir=\$PWD\n";
      print EXE_COM_FILE "scripthome=\$(dirname \$0)\n";
      print EXE_COM_FILE "cd \${scripthome}\n";
      print EXE_COM_FILE "# Compile and elaborate the testbench\n";
      print EXE_COM_FILE "vsim -batch -do \"do $fname_compilescript\"\n";
      print EXE_COM_FILE "retval=\$?\n";
      print EXE_COM_FILE "cd \${rundir}\n";
      print EXE_COM_FILE "exit \${retval}\n";
    } elsif (isWindowsOS()) {
      print EXE_COM_FILE "set rundir=\%cd\%\n";
      print EXE_COM_FILE "set scripthome=\%\~dp0\n";
      print EXE_COM_FILE "cd %scripthome%\n";
      print EXE_COM_FILE "vsim -batch -do \"do $fname_compilescript\"\n";
      print EXE_COM_FILE "set exitCode=%ERRORLEVEL%\n";
      print EXE_COM_FILE "cd %rundir%\n";
      print EXE_COM_FILE "exit /b %exitCode%\n";
    }
    close(EXE_COM_FILE);
    if(isLinuxOS()) {
      system("chmod +x $cosimdir/$fname_exe_com_script"); 
    }
}

sub compile_verification_project() {
    # Working directories
    my $cosimdir = "$g_work_dir/$cosim_work_dir";
    my $fname_exe_com_script = isLinuxOS() ? 'compile.sh' : 'compile.cmd';
    # Compile the cosim design in the cosim directory
    $orig_dir = acl::File::abs_path('.');
    chdir $cosimdir or mydie("Can't change into dir $g_work_dir: $!\n");
    if (isLinuxOS()) {
      @cmd_list = ("./$fname_exe_com_script");
    } elsif (isWindowsOS()) {
      @cmd_list = ("$fname_exe_com_script");
    }

    $return_status = mysystem_full(
      {'stdout' => $project_log,'stderr' => $project_log,
       'title' => 'Elaborate verification testbench'},
      @cmd_list);
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");

    # Missing license is such a common problem, let's give a special message
    if($return_status == 4) {
      my @temp;
      if (isWindowsOS()) {
        @temp = `where vsim`;
      } else {
        @temp = `which vsim`;
      }
      chomp(my $vsim_path = shift @temp);

      mydie("Missing simulator license for $vsim_path.  Either:\n" .
            "  1) Ensure you have a valid ModelSim license\n" .
            "  2) Use the --simulator none flag to skip the verification flow\n");
    } elsif($return_status == 127) {
    # same for Modelsim not installed on the PATH
        mydie("Error accessing ModelSim.  Please ensure you have a valid ModelSim installation on your path.\n" .
              "       Check your ModelSim installation with \"vmap -version\" \n"); 
    } elsif($return_status != 0) {
      mydie("Cosim testbench elaboration failed.\n");
    }
}

sub gen_qsys_script(@) {
    my @components = @_;

    my $qsys_ext = qii_is_pro() ? ".ip" : ".qsys";

    foreach (@components) {
        # Generate the tcl for the system
        my $tclfilename = "components/$_/$_.tcl";
        open(my $qsys_script, '>', "$tclfilename") or die "Could not open file '$tclfilename' $!";

        print $qsys_script <<SCRIPT;
package require -exact qsys 16.1

# create the system with the name
create_system $_

# set project properties
set_project_property HIDE_FROM_IP_CATALOG false
set_project_property DEVICE_FAMILY "${dev_family}"
set_project_property DEVICE "${dev_part}"

# adding the ip for which the variation has to be created for
add_instance ${_}_internal_inst ${_}_internal
set_instance_property ${_}_internal_inst AUTO_EXPORT true

# save the Qsys file
save_system "$_$qsys_ext"
SCRIPT
        close $qsys_script;
        push @cleanup_list, $g_work_dir."/$tclfilename";
    }
}

sub run_qsys_script(@) {
    my @components = @_;

    my $curr_dir = acl::File::abs_path('.');
    chdir "components" or mydie("Can't change into dir components: $!\n");

    foreach (@components) {
        chdir "$_" or mydie("Can't change into dir $_: $!\n");

        # Generate the verilog for the simulation system
        @cmd_list = ('qsys-script',
                     "--script=$_.tcl");
      if (qii_is_pro()) { push(@cmd_list, ('--quartus-project=none')); }
        mysystem_full(
            {'stdout' => $project_log, 'stderr' => $project_log, 'title' => 'Generate component QSYS script'}, 
            @cmd_list) == 0 or mydie();

        # This is a temporary workaround so that the IP can be seen in the GUI
        # See case:375326
      if (qii_is_pro()) {
            @cmd_list = ('qsys-generate', '--quartus-project=none', '--synthesis', '--ipxact', "${_}.ip");
            mysystem_full(
                {'stdout' => $project_log, 'stderr' => $project_log, 'title' => 'Generate component QSYS ipxact'}, 
                @cmd_list) == 0 or mydie();
        }

        chdir ".." or mydie("Can't change into dir ..: $!\n");
    }
    chdir $curr_dir or mydie("Can't change into dir $curr_dir: $!\n");
}

sub post_process_msim_file(@) {
  my ($file,$libpath) = @_;
  open(FILE, "<$file") or die "Can't open $file for read";
  my @lines;
  while(my $line = <FILE>) {
    # fix library paths
    $line =~ s|\./libraries/|$libpath/libraries/|g;
    # fix vsim version call because it does not work in batch mode
    $line =~ s|\[\s*vsim\s*-version\s*\]|\$VSIM_VERSION_STR|g;
    push(@lines,$line);
  }
  close(FILE);
  open(OFH,">$file") or die "Can't open $file for write";
  foreach my $line (@lines) {
    print OFH $line;
  }
  close(OFH);
  return 0;
}

sub post_process_qsys_files(@) {
    my @components = @_;

    my $return_status = 0;
    foreach (@components) {
        my $qsys_ip_file =  qii_is_pro() ? "components/$_/$_/$_.ipxact" :
                                              "components/$_/$_.qsys";
        # Read in the current QSYS file
        open (FILE, "<$qsys_ip_file") or die "Can't open $qsys_ip_file for read";
        my @lines;
        while (my $line = <FILE>) {
            # this organizes the components in the IP catalog under the same HLS/ directory
            if (qii_is_pro()) {
                $line =~ s/Altera Corporation/HLS/g;
            } else {
                $line =~ s/categories=""/categories="HLS"/g;
            }
            push(@lines, $line);
        }
        close(FILE);
        # Write out the modified QSYS file
        open (OFH, ">$qsys_ip_file") or die "Can't open $qsys_ip_file  for write";
        foreach my $line (@lines) {
                print OFH $line;
        }
        close(OFH);
    }
    return $return_status;
}

sub create_ip_folder(@) {
  my @components = @_;
  my $OCLROOTDIR = $ENV{'INTELFPGAOCLSDKROOT'};

  my $qsys_ext = qii_is_pro() ? ".ip" : ".qsys";

  foreach (@components) {
    my $component = $_;
    open(FILELIST, "<$component.files") or die "Can't open $component.files for read";
    while(my $file = <FILELIST>) {
      chomp $file;
      if($file =~ m|\$::env\(INTELFPGAOCLSDKROOT\)/|) {
        $file =~ s|\$::env\(INTELFPGAOCLSDKROOT\)/||g;
        acl::File::copy("$OCLROOTDIR/$file", "components/".$component."/".$file);
      } else {
        acl::File::copy($file, "components/".$component."/".$file);
        push @cleanup_list, $g_work_dir.'/'.$file;
      }
    }
    close(FILELIST);

    # if it exists, copy the slave CSR header file
    acl::File::copy($component."_csr.h", "components/".$component."/".$component."_csr.h");

    # if it exists, copy the inteface file for each component
    acl::File::copy($component."_interface_structs.v", "components/".$component."/"."interface_structs.v");

    # cleanup
    push @cleanup_list, $g_work_dir.'/'.$component."_interface_structs.v";
    push @cleanup_list, $g_work_dir.'/'.$component."_csr.h";
    push @cleanup_list, $g_work_dir.'/'.$component.".files";
  }
  acl::File::copy("interface_structs.v", "components/interface_structs.v");
  push @cleanup_list, $g_work_dir.'/interface_structs.v';
  return 0;
}

sub create_qsys_components(@) {
    my @components = @_;
    create_ip_folder(@components);
    gen_qsys_script(@components);
    run_qsys_script(@components);
    post_process_qsys_files(@components);
}

sub get_qsys_output_dir($) {
   my ($target) = @_;

   my $dir = ($target eq "SIM_VERILOG") ? "simulation" : "synthesis";

   if (qii_is_pro() or $dev_family eq "Arria 10") {
      $dir = ($target eq "SIM_VERILOG")   ? "sim"   :
             ($target eq "SYNTH_VERILOG") ? "synth" :
                                            "";
   }

   return $dir;
}

sub get_qsys_sim_dir() {
   my $qsysdir = $tbname.'/'.get_qsys_output_dir("SIM_VERILOG");

   return $qsysdir;
}

sub get_sim_script_dir() {

   my $qsysdir = get_qsys_sim_dir();
   my $simscriptdir = $qsysdir.'/mentor';

   return $simscriptdir;
}

sub generate_top_level_qii_verilog($@) {
    my ($qii_project_name, @components) = @_;
    my %clock2x_used;
    my %component_portlists;
    foreach (@components) {
      #read in component module from file and parse for portlist
      my $example = '../components/'.$_.'/'.$_.'_inst.v';
      open (FILE, "<$example") or die "Can't open $example for read";
      #parse for portlist
      my $in_module = 0;
      while (my $line = <FILE>) {
        if($in_module) {
          if($line =~ m=^ *\.([a-z]+)=) {
          }
          if($line =~ m=^\s*\.(\S+)\s*\( \),*\s+// (\d+)-bit \S+ (input|output)=) {
            my $hi = $2 - "1";
            my $range = "[$hi:0]";
            push(@{$component_portlists{$_}}, {'dir' => $3, 'range' => $range, 'name' => $1});
            if($1 eq "clock2x") {
              push(@{$clock2x_used{$_}}, 1);
            }
          }
        } else {
          if($line =~ m|^$_ ${_}_inst \($|) {
            $in_module = 1;
          }
        }
      }
      close(FILE);
    }

    #output top level
    open (OFH, ">${qii_project_name}.v") or die "Can't open ${qii_project_name}.v for write";
    print OFH "module ${qii_project_name} (\n";

    #ports
    print OFH "\t  input logic resetn\n";
    print OFH "\t, input logic clock\n";
    if (scalar keys %clock2x_used) {
        print OFH "\t, input logic clock2x\n";
    }
    foreach (@components) {
        my @portlist = @{$component_portlists{$_}};
        foreach my $port (@portlist) {
            #skip clocks and reset
            my $port_name = $port->{'name'};
            if ($port_name eq "resetn" or $port_name eq "clock" or $port_name eq "clock2x") {
                next;
            }
            #component ports
            print OFH "\t, $port->{'dir'} logic $port->{'range'} ${_}_$port->{'name'}\n";
        }
    }
    print OFH "\t);\n\n";

    if ($qii_io_regs) {
        #declare registers
        foreach (@components) {
            my @portlist = @{$component_portlists{$_}};
            foreach my $port (@portlist) {
                my $port_name = $port->{'name'};
                #skip clocks and reset
                if ($port_name eq "resetn" or $port_name eq "clock" or $port_name eq "clock2x") {
                    next;
                }
                print OFH "\tlogic $port->{'range'} ${_}_${port_name}_reg;\n";
            }
        }

        #wire registers
        foreach (@components) {
            my @portlist = @{$component_portlists{$_}};
            print OFH "\n\n\talways @(posedge clock) begin\n";
            foreach my $port (@portlist) {
                my $port_name = "$port->{'name'}";
                #skip clocks and reset
                if ($port_name eq "resetn" or $port_name eq "clock" or $port_name eq "clock2x") {
                    next;
                }

                $port_name = "${_}_${port_name}";
                if ($port->{'dir'} eq "input") {
                    print OFH "\t\t${port_name}_reg <= ${port_name};\n";
                } else {
                    print OFH "\t\t${port_name} <= ${port_name}_reg;\n";
                }
            }
            print OFH "\tend\n";
        }
    }

    #reset synchronizer
    print OFH "\n\n\treg [2:0] sync_resetn;\n";
    print OFH "\talways @(posedge clock or negedge resetn) begin\n";
    print OFH "\t\tif (!resetn) begin\n";
    print OFH "\t\t\tsync_resetn <= 3'b0;\n";
    print OFH "\t\tend else begin\n";
    print OFH "\t\t\tsync_resetn <= {sync_resetn[1:0], 1'b1};\n";
    print OFH "\t\tend\n";
    print OFH "\tend\n";

    #component instances
    my $comp_idx = 0;
    foreach (@components) {
        my @portlist = @{$component_portlists{$_}};
        print OFH "\n\n\t${_} ${_}_inst (\n";
        print OFH "\t\t  .resetn(sync_resetn[2])\n";
        print OFH "\t\t, .clock(clock)\n";
        if (exists $clock2x_used{$_}) {
            print OFH "\t\t, .clock2x(clock2x)\n";
        }
        foreach my $port (@portlist) {
            my $port_name = $port->{'name'};
            #skip clocks and reset
            if ($port_name eq "resetn" or $port_name eq "clock" or $port_name eq "clock2x") {
                next;
            }
            my $reg_name_suffix = $qii_io_regs ? "_reg" : "";
            my $reg_name = "${_}_${port_name}${reg_name_suffix}";
            print OFH "\t\t, .${port_name}(${reg_name})\n";
        }
        print OFH "\t);\n\n";
        $comp_idx = $comp_idx + 1
    }
    print OFH "\n\nendmodule\n";
    close(OFH);

    return scalar keys %clock2x_used;
}

sub generate_qpf($@) {
  my ($qii_project_name) = @_;
  open (OUT_QPF, ">${qii_project_name}.qpf") or die;
  print OUT_QPF "# This Quartus project file sets up a project to measure the area and fmax of\n";
  print OUT_QPF "# your components in a full Quartus compilation for the targeted device\n";
  print OUT_QPF "PROJECT_REVISION = ${qii_project_name}";
  close (OUT_QPF);
}

sub generate_qsf($@) {
    my ($qii_project_name, @components) = @_;

    my $qsys_ext  = qii_is_pro() ? ".ip" : ".qsys";
    my $qsys_type = qii_is_pro() ? "IP" : "QSYS";

    open (OUT_QSF, ">${qii_project_name}.qsf") or die;
    print OUT_QSF "# This Quartus settings file sets up a project to measure the area and fmax of\n";
    print OUT_QSF "# your components in a full Quartus compilation for the targeted device\n";
    print OUT_QSF "\n";
    print OUT_QSF "# Family and device are derived from the -march argument to i++\n";
    print OUT_QSF "set_global_assignment -name FAMILY \"${dev_family}\"\n";
    print OUT_QSF "set_global_assignment -name DEVICE ${dev_part}\n";

    print OUT_QSF "# This script parses the Quartus reports and generates a summary that can be viewed via reports/report.html or reports/lib/json/quartus.json\n";
    # add call to parsing script after STA is run
    my $qii_rpt_tcl = "generate_report.tcl";
    print OUT_QSF "set_global_assignment -name POST_FLOW_SCRIPT_FILE \"quartus_sh:${qii_rpt_tcl}\"\n";

    print OUT_QSF "\n";
    print OUT_QSF "# Files implementing a basic registered instance of each component\n";
    print OUT_QSF "set_global_assignment -name TOP_LEVEL_ENTITY ${qii_project_name}\n";
    print OUT_QSF "set_global_assignment -name SDC_FILE ${qii_project_name}.sdc\n";
    # add component Qsys files to project
    foreach (@components) {
      print OUT_QSF "set_global_assignment -name ${qsys_type}_FILE ../components/$_/$_$qsys_ext\n";
    }
    # add generated top level verilog file to project
    print OUT_QSF "set_global_assignment -name SYSTEMVERILOG_FILE ${qii_project_name}.v\n";

    print OUT_QSF "\n";
    print OUT_QSF "# Partitions are used to separate the component logic from the project harness when tallying area results\n";
    print OUT_QSF "set_global_assignment -name PARTITION_NETLIST_TYPE SOURCE -section_id component_partition\n";
    print OUT_QSF "set_global_assignment -name PARTITION_FITTER_PRESERVATION_LEVEL PLACEMENT_AND_ROUTING -section_id component_partition\n";
    foreach (@components) {
      if (qii_is_pro()) {
        print OUT_QSF "set_instance_assignment -name PARTITION component_${_} -to \"${_}:${_}_inst\"\n";
      } else {
        print OUT_QSF "set_instance_assignment -name PARTITION_HIERARCHY component_${_} -to \"${_}:${_}_inst\" -section_id component_partition\n";
      }
    }

    print OUT_QSF "\n";
    print OUT_QSF "# No need to generate a bitstream for this compile so save time by skipping the assembler\n";
    print OUT_QSF "set_global_assignment -name FLOW_DISABLE_ASSEMBLER ON\n";

    print OUT_QSF "\n";
    print OUT_QSF "# Use the --quartus-seed flag to i++, or modify this setting to run other seeds\n";
    my $seed = 0;
    my $seed_comment = "# ";
    if (defined $qii_seed ) {
      $seed = $qii_seed;
      $seed_comment = "";
    }
    print OUT_QSF $seed_comment."set_global_assignment -name SEED $seed";


    print OUT_QSF "\n";
    print OUT_QSF "# This assignment configures all component I/Os as virtual pins to more accurately\n";
    print OUT_QSF "# model placement and routing in a larger system\n";
    my $qii_vpins_comment = "# ";
    if ($qii_vpins) {
      $qii_vpins_comment = "";
    }
    print OUT_QSF $qii_vpins_comment."set_instance_assignment -name VIRTUAL_PIN ON -to *";

    close(OUT_QSF);
}

sub generate_sdc($$) {
  my ($qii_project_name, $clock2x_used) = @_;

  open (OUT_SDC, ">${qii_project_name}.sdc") or die;
  print OUT_SDC "create_clock -period 1 clock\n";                                                                                                          
  if ($clock2x_used) {                                                                                                                                        
    print OUT_SDC "create_clock -period 0.5 clock2x\n";                                                                                           
  }                                                                                                                                                           
  close (OUT_SDC);
}

sub generate_quartus_ini() {
  open(OUT_INI, ">quartus.ini") or die;
  #temporary work around for A10 compiles
  if ($dev_family eq "Arria 10") {
    print OUT_INI "a10_iopll_es_fix=off\n";
  }
  if ($qii_dsp_packed) {
    print OUT_INI "fsv_mac_merge_for_density=on\n";
  }
  close(OUT_INI);
}

sub generate_report_script($@) {
  my ($qii_project_name, $clock2x_used, @components) = @_;
  my $qii_rpt_tcl = acl::Env::sdk_root()."/share/lib/tcl/hls_qii_compile_report.tcl";
  my $html_rpt_tcl = acl::Env::sdk_root()."/share/lib/tcl/hls_quartus_html_report.tcl";
  open(OUT_TCL, ">generate_report.tcl") or die;
  print OUT_TCL "# This script has the logic to create a summary report\n";
  print OUT_TCL "source $qii_rpt_tcl\n";
  print OUT_TCL "source $html_rpt_tcl\n";
  print OUT_TCL "# These are generated by i++ based on the components\n";
  print OUT_TCL "set show_clk2x   $clock2x_used\n";
  print OUT_TCL "set components   [list " . join(" ", @components) . "]\n";
  print OUT_TCL "# This is where we'll generate the report\n";
  print OUT_TCL "set report_name  \"../reports/lib/json/quartus.json\"\n";
  print OUT_TCL "# These get sent to the script by Quartus\n";
  print OUT_TCL "set project_name [lindex \$quartus(args) 1]\n";
  print OUT_TCL "set project_rev  [lindex \$quartus(args) 2]\n";
  print OUT_TCL "# This call creates the report\n";
  print OUT_TCL "generate_report \$project_name \$project_rev \$report_name \$show_clk2x \$components\n"; 
  print OUT_TCL "update_html_report_data\n";
  close(OUT_TCL);
}

sub generate_qii_project {
    # change to the working directory
    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");
    my @components = get_generated_components();
    if (not -d "$quartus_work_dir") {
        mkdir "$quartus_work_dir" or mydie("Can't make dir $quartus_work_dir: $!\n");
    }
    chdir "$quartus_work_dir" or mydie("Can't change into dir $quartus_work_dir: $!\n");

    my $clock2x_used = generate_top_level_qii_verilog($qii_project_name, @components);
    generate_report_script($qii_project_name, $clock2x_used, @components);
    generate_qsf($qii_project_name, @components);
    generate_qpf($qii_project_name);
    generate_sdc($qii_project_name, $clock2x_used);
    generate_quartus_ini();

    # change back to original directory
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");
}

sub compile_qii_project($) {
    my ($qii_project_name) = @_;

    # change to the working directory
    chdir $g_work_dir."/$quartus_work_dir" or mydie("Can't change into dir $g_work_dir/$quartus_work_dir: $!\n");

    @cmd_list = ('quartus_sh',
            "--flow",
            "compile",
            "$qii_project_name");

    mysystem_full(
        {'stdout' => $project_log, 'stderr' => $project_log, 'title' => 'run Quartus compile'}, 
        @cmd_list) == 0 or mydie();

    # change back to original directory
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");

    return $return_status;
}

# Accept a filename dir/base.ext and return (dir/base, .ext)
sub parse_extension {
  my $filename = shift;
  my ($ext) = $filename =~ /(\.[^.\/\\]+)$/;
  my $base = $filename;
  if(defined $ext) {
    $base =~ s/$ext$//;
  }
  return ($base, $ext);
}

sub open_time_log_file {
  # Process $time_log. If defined, then treat it as a file name 
  # (including "-", which is stdout).
  # Code copied from aoc.pl
  if ($time_log) {
    my $fh;
    if ($time_log ne "-") {
      # Overwrite the log if it exists
      open ($fh, '>', $time_log) or mydie ("Couldn't open $time_log for time output.");
    } else {
      # Use STDOUT.
      open ($fh, '>&', \*STDOUT) or mydie ("Couldn't open stdout for time output.");
    }
    # From this point forward, $time_log is now a file handle!
    $time_log = $fh;
  }
}

sub run_quartus_compile($) {
    my ($qii_project_name) = @_;
    print "Run Quartus\n" if $verbose;
    compile_qii_project($qii_project_name);
}

sub main {
    my $cmd_line = $prog . " " . join(" ", @ARGV);
    $all_ipp_args = $cmd_line;
    if ( isWindowsOS() ){
      $default_object_extension = ".obj";
    }    
    parse_args();

    if ( $emulator_flow ) {$macro_type_string = "NONE";}
    else                  {$macro_type_string = "VERILOG";}

    # Process all source files one by one
    while ($#source_list >= 0) {
      my $source_file = shift @source_list;
      my $object_name = undef;
      if($object_only_flow_modifier) {
        if ( !($project_name eq 'a') or !($executable eq isWindowsOS() ? "a.exe" : "a.out")) {
          # -c, so -o name applies to object file, don't add .o
          $object_name = $project_name;
        } else {
          # reuse source base name
          $object_name = get_name_core($source_file).$default_object_extension;
        }
      } else {
          # object file name is temporary, make sure we do not collide with parallel compiles
          $object_name = get_name_core($source_file).$$.$default_object_extension;
      }
      if ( $emulator_flow ) {
        emulator_compile($source_file, $object_name);
      } else {
        my $work_dir=$object_name.'.'.$$.'.tmp';
        acl::File::make_path($work_dir) or mydie($acl::File::error.' While trying to create '.$work_dir);
        push @cleanup_list, $work_dir;

        if (!$RTL_only_flow_modifier && !$soft_ip_c_flow_modifier) {
          testbench_compile($source_file, $object_name, $work_dir);
        } else {
          remove_named_files($object_name);
        }
        fpga_parse($source_file, $object_name, $work_dir);
      }
    }

    if ($object_only_flow_modifier) { myexit('Object generation'); }

    setup_linkstep($cmd_line) unless  ($x86_linkstep_only); #unpack objects and setup project directory

    if (!$emulator_flow && !$x86_linkstep_only){
    # Now do the 'real' compiles depend link step, wich includes llvm cmpile for
    # testbench and components
    if ($#fpga_IR_list >= 0) {
      find_board_spec();
      generate_fpga(@fpga_IR_list);
    }

      if (!($cosim_simulator eq "NONE") && $#fpga_IR_list >= 0) {
        hls_sim_generate_verilog(get_name_core($project_name)) if not $RTL_only_flow_modifier;
    }

      if ($#fpga_IR_list >= 0) {
      generate_qii_project();
    }

      # Run ModelSim compilation,
      if ($#fpga_IR_list >= 0) {
      compile_verification_project() if not $RTL_only_flow_modifier;
      } 
    } #emulation

    if (!$cosim_linkstep_only && $#object_list >= 0) {
      link_x86($executable, $emulator_flow);
    }

    # Run Quartus compile
    if ($qii_flow && $#fpga_IR_list >= 0) {
      run_quartus_compile($qii_project_name);
    }

    myexit("Main flow");
}

main;
