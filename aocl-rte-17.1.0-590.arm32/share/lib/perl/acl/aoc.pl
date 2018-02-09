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


# Intel(R) FPGA SDK for OpenCL(TM) kernel compiler.
#  Inputs:  A .cl file containing all the kernels
#  Output:  A subdirectory containing: 
#              Design template
#              Verilog source for the kernels
#              System definition header file
#
# 
# Example:
#     Command:       aoc foobar.cl
#     Generates:     
#        Subdirectory foobar including key files:
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
require acl::Common;
require acl::File;
require acl::Pkg;
require acl::Env;
require acl::Board_migrate;
require acl::Report;
require acl::Incremental;
use acl::Report qw(escape_string);

my $prog = 'aoc';
my $emulatorDevice = 'EmulatorDevice'; #Must match definition in acl.h
my $return_status = 0;

#Filenames
my $input_file = undef; # might be relative or absolute
my @given_input_files; # list of input files specified on command line.
my $output_file = undef; # -o argument
my $output_file_arg = undef; # -o argument
my $srcfile = undef; # might be relative or absolute
my $objfile = undef; # might be relative or absolute
my $x_file = undef; # might be relative or absolute
my $pkg_file = undef;
my $src_pkg_file = undef;
my $absolute_srcfile = undef; # absolute path
my $absolute_efispec_file = undef; # absolute path of the EFI Spec file
my $absolute_profilerconf_file = undef; # absolute path of the Profiler Config file
my $marker_file = ".project.marker"; # relative path of the marker file to the project working directory

#directories
my $orig_dir = undef; # absolute path of original working directory.
my $work_dir = undef; # absolute path of the project working directory

#library-related
my @lib_files;
my @lib_paths;
my @resolved_lib_files;
my @lib_bc_files = ();
my $created_shared_aoco = undef;
my $ocl_header_filename = "opencl_lib.h";
my $ocl_header = $ENV{'INTELFPGAOCLSDKROOT'}."/share/lib/acl"."/".$ocl_header_filename;

# Executables
my $clang_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/aocl-clang";
my $opt_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/aocl-opt";
my $link_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/aocl-link";
my $llc_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/aocl-llc";
my $sysinteg_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/system_integrator";
my $detectchanges_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/detect_changes";
my $aocl_libedit_exe = "aocl library";

#Log files
my $fulllog = undef;
my $quartus_log = 'quartus_sh_compile.log';

my $regtest_mode = 0;

#Flow control
my $parse_only = 0; # Hidden option to stop after clang.
my $opt_only = 0; # Hidden option to only run the optimizer
my $verilog_gen_only = 0; # Hidden option to only run the Verilog generator
my $ip_gen_only = 0; # Hidden option to only run up until ip-generate, used by sim
my $high_effort = 0;
my $skip_qsys = 0; # Hidden option to skip the Qsys generation of "system"
my $compile_step = 0; # stop after generating .aoco
my $vfabric_flow = 0;
my $griffin_flow = 1; # Use DSPBA backend instead of HDLGeneration
my $generate_vfabric = 0;
my $reuse_vfabrics = 0;
my $vfabric_seed = undef;
my $custom_vfab_lib_path = undef;
my $emulator_flow = 0;
my $soft_ip_c_flow = 0;
my $accel_gen_flow = 0;
my $run_quartus = 0;
my $standalone = 0;
my $hdl_comp_pkg_flow = 0; #Forward args from 'aoc' to 'aocl library'
my $c_acceleration = 0; # Hidden option to skip clang for C Acceleration flow.
# TODO: Deprecate old simulation mode
my $new_sim_mode  = 0; #Hidden option to generate ModelSim aocx
my $is_pro_mode = 0;
my $cosim_64bit  = 0; # Simulator is 64 bit version
my $sim_debug  = 0; #Hidden option to generate ModelSim aocx with debug symbols
my $sim_debug_depth; #Hidden option set logging depth for verilog symbols.
my $simulation_mode = 0; #Hidden option to generate full board verilogs targeted for simulation  (aoc -s foo.cl)
my $no_automigrate = 0; #Hidden option to skip BSP Auto Migration
my $emu_optimize_o3 = 0; #Apply -O3 optimizations for the emulator flow
my $emu_ch_depth_model = 'default'; #Channel depth mode in emulator flow 
my $fast_compile_on = 0; #Allows user to speed compile times while suffering performance hit
my $incremental = 0; #Allows user to speed compile times while suffering performance hit
my $save_partition_file = ''; #Allows user to speed compile times while suffering performance hit
my $set_partition_file = ''; #Allows user to speed compile times while suffering performance hit
my $soft_region_on = ''; #Add soft region settings
my $user_defined_board = 0; # True if the user specifies -board option

#Flow modifiers
my $optarea = 0;
my $force_initial_dir = '.'; # absolute path of original working directory the user told us to use.
my $use_ip_library = 1; # Should AOC use the soft IP library
my $use_ip_library_override = 1;
my $do_env_check = 1;
my $dsploc = '';
my $ramloc = '';
my @additional_qsf = ();

#Output control
my $verbose = 0; # Note: there are two verbosity levels now 1 and 2
my $quiet_mode = 0; # No messages printed if quiet mode is on
my $report = 0; # Show Throughput and area analysis
my $estimate_throughput = 0; # Show Throughput guesstimate
my $debug = 0; # Show debug output from various stages
my $time_log_fh = undef; # Time various stages of the flow; if not undef, it is a 
                      # file handle (could be STDOUT) to which the output is printed to.
my $time_log_filename = undef; # Filename from --time arg
my $time_passes = 0; # Time LLVM passes. Requires $time_log_fh to be valid.
# Should we be tidy? That is, delete all intermediate output and keep only the output .aclx file?
# Intermediates are removed only in the --hw flow
my $dotfiles = 0;
my $pipeline_viewer = 0;
my $tidy = 0; 
my $save_temps = 0;
my $pkg_save_extra = 0; # Save extra items in the package file: source, IR, verilog
my $library_debug = 0;

# Yet unclassfied
my $save_last_bc= 0; #don't remove final bc if we are generating profiles
my $disassemble = 0; # Hidden option to disassemble the IR
my $fit_seed = undef; # Hidden option to set fitter seed
my $profile = 0; # Option to enable profiling
my $program_hash = undef; # SHA-1 hash of program source, options, and board.
my $triple_arg = '';
my $dash_g = 1;      # Debug info enabled by default. Use -g0 to disable.
my $user_dash_g = 0; # Indicates if the user explictly compiled with -g.

# Regular arguments.  These go to clang, but does not include the .cl file.
my @user_clang_args = ();

# The compile options as provided by the clBuildProgram OpenCL API call.
# In a standard flow, the ACL host library will generate the .cl file name, 
# and the board spec, so they do not appear in this list.
my @user_opencl_args = ();

my $opt_arg_after   = ''; # Extra options for opt, after regular options.
my $llc_arg_after   = '';
my $clang_arg_after = '';
my $sysinteg_arg_after = '';
my $max_mem_percent_with_replication = 100;
my @additional_migrations = ();
my @blocked_migrations = ();

my $efispec_file = undef;
my $profilerconf_file = undef;
my $dft_opt_passes = '--acle ljg7wk8o12ectgfpthjmnj8xmgf1qb17frkzwewi22etqs0o0cvorlvczrk7mipp8xd3egwiyx713svzw3kmlt8clxdbqoypaxbbyw0oygu1nsyzekh3nt0x0jpsmvypfxguwwdo880qqk8pachqllyc18a7q3wp12j7eqwipxw13swz1bp7tk71wyb3rb17frk3egwiy2e7qjwoe3bkny8xrrdbq1w7ljg70g0o1xlbmupoecdfluu3xxf7l3dogxfs0lvm7jlzmh8pv3kzlkjxz2acnczpy2g1wkvi7jlzmrpouhh3qrjxlga33czpygdbwgpin2t13svzq3kzmtfxmxffmowonxdb0uui32q3mju7atjmnjvbzxdsmczpyrkf0evzexy1qgfpt3gznj0318a7mcporxgbyw0oprlemyy7atj7me0b1rauqiypfrj38uui3rukqa0od3gbnfvc2xd33czpyrf70tji1guolg0odcvorlvc8xfbqb17frkb0t8zp2t13svzttdoluu3xxfhmivolgfbyw0o7xtclgvz0cvorlvcngfml8yplgf38uui32qqquwotthsly8xxgd33czpyrfu0evzp2qmqwvzltk72tfxm2dblijzm2hfwwpowxyolu07ekh3nupb3rkmni8pdxdu0wyi880qqkvot3jfnupblgd3lo87frk77gpo880qqkyzuhdfnfy3xxf7m88zt8vs0r0zb2lcna8pl3aorlvcvgsmmvyzsxg7etfmiresqryp83bknywbp2kbmb0zgggzwtfmirebmrwo23g1nhwb1rkmniworrj1wkpioglctgfpttjhljpb1ra1q38zq2vs0rvzrrlcljjzucfqnldx0jpsmvjog2g3eepin2tzmhjzy1bkny8xxxkcnvvpagkuwwdo880qqkwou3gfny8cvrabqoypaxbbyw0ot2qumywpkhkqmydc3rzbtijz12j10g0zorekqjwoecvorlvcvxafq187frkm7wjz1xy1mju7atjfnevcbrzbtijzsrgfwhdmire1nsvom3gzmy0x18a7q3wp12j7eqwipxw13swz8bvorlvcvxafq187frkbew0zq2q3lk0py1bkny8xxxkcnvvpagkuwwdo880qqk8packbmupbqrzbtijzsrgfwhdmirekmg8ps3h72tfxmrafmiwoljg7wudop2w3ldjpacvorlvc32jsqb17frkk0udi3xukls0o0cvorlvcqxf7q1w7ljg70qyitxyzqsypr3gknt0318a7qp8oaxfbyw0owxqolg8zw3gknr0318a7mvvp1gfbwepow2w3qgfptcd1ml0b7xd1q3ypdgg38uui3xwzlg07ekh3nuwcmgd33czpyrfu0evzp2qmqwvzltk72tfxmgssm80oyrgkwrpii2wctgfpttdzqj8xwgpsmv0zl2kc0uui3xuolswoscfqqkycqrzbtijzwxgfwrpopxwzqg07ekh3nyjxxxkcno8z1rjbwtfmireoqjpo23golj0318a7mvvpfgdbwgjz7jlzqdjp2ckorlvczxazl887frkc7wdmirekmswo23gknj8xmxk33czpyxgf0jdor20qqk0okcdonj0318a7m3pp1rghwedmirezmd8zahholqvb0jpsmv0zwgdb7uvm7jlzmajpscdorlvcqgskq10pggjuetfmiretqkvo33j72tfxmrafmiwoljg70kyirrltma07ekh3nedxqrj7mi8pu2hs0uvm7jlzmg8iahp3qh8cyrzbtijza2k77lpo1x713svz33gslkwxz2dunvpzwxbbyw0otrezmy07ekh3nrdbxrzbtijza2jk0rvzkrlcnr07ekh3nedxqrj7mi8pu2hs0uvm7jlzmfyofcdorlvcyrsmncyzq2hs0yvm7jlzmgvoecvorlvc7rd7mcw7ljg70gpizxutqddzbtjbnr0318a7mzpp8xd70wdi22qqqg07ekh3njwblgs3nczpyxjb0tjo7jlzmyposcfhlh8vwgd7lb17frkzwewi22etmgvzecvorlvcmxasm80oa2jm7ydo880qqkpzuhd1meyclrzbtijzlgju0uui3xueqddp03k1mtfxmgfmnx87frk1wwpop2tzldvoy1bkny8cvxj1m7joljg70qyip2qqqg07ekh3lljxlgamnc0ot8vs0rdi7gu7qgpoecfoqjdx0jpsmvypfxdbwgyo1re1qu07ekh3ltjcrgjbqb17frk3egwizrl3lgvo03jzmevcqrzbtijzrrkh0uui3xleqjwzekh3njwbc2kbmczpy2hswk8zbglzldvz33bkny8c8rd33czpyxh1wwjop2w13svzehkqny8cvra7lb17frkcegpoirumqspof3bknyyc2gs7mb0psrf38uui3xleqtyz2tjhlldb0jpsmv0zy2j38uui3xleqtyz2tjhllvbyrzbtijzrxgz7tppt20qqkpoe3hhlgyc18a7mo8za2vs0rpiixyolddp33g3nj0318a7q88zargo7udmireeqspzekh3nuvcmgd7n88z8xbbyw0o0re1mju7atj3my8cvgfml88z3xg38uui3xwzqg07ekh3lkpbz2jmr88zwxbbyw0or2wuqsdoe3bkny8xxgscnzyzs2hq7tjzbrlqqgfpttdzmlpb1xk33czpyxfm7wdioxy1mypokhf72tfxmgfcmv8zt8vs0rjiorlclgfpttdqnq0bvgsom7w7ljg7whvib20qqkvzs3jfntvbmgssmxw7ljg70gpizxutqddzbtjbnr0318a7mzpp8xd70wdi22qqqg07ekh3ltvc1rzbtijzwxgfwrpopxwzqg07ekh3lr8xdgj3nczpygkuwk0o1ru3lu07ekh3lqyx1gabtijz8xfh0qjzw2wonju7atjmltwclgd7n887frk7ehpo32w13svzn3k1medcfrzbtijz72jm7qyokx713svzm3gzlh0x18a7m2yp82jbyw0oz2wolhyzy1bknywcmgd33czpy2kcek8zbge1nryz8hdhlk8c3gfcnzvpfxbbyw0omgyqmju7atjznrdbugd33czpyxj70uvm7jlzqu8pfcdfnedcfxfomxw7ljg7we0zwgu1lkwokhkqquu3xxfuqijomrkf0e8obgl1qgfpthhhntfxm2j33czpyrf70tji1gukmeyzekh3lq8clxdbmczpy2kz0y8z7rwbmryz3cvorlvcqxf1qoyz1gfbwhji880qqkwzt3k72tfxm2duq78o32vs0r8obxyzqjvo0td72tfxmrafm28z1rfz7qjz3xqctgfpttd3nuwx72kuq08zt8vs0ryioguumavoy1bknywcmgd33czpy2kc0rdo880qqkjznhh72tfxmrd7mcw7ljg70qyitxyzqsypr3gknt0318a7q1dodrjm7tdi7jlzqhwpshjmlqy3xxfkmc8pt8vs0rvzrrl7mu8zf3bknyjcvxammb0pljg70edoz20qqkyo33jcnt0318a7q3doggdu0tji7jlzqa8z0cg72tfxmxdoliw7ljg70gpizxutqddzb3bknydcwrzbtijzqrkbwtfmirekmswzeca3mg8cwrkuqivzt8vs0rwzb2qzqa07ekh3lhpb72a7lxvp12gbyw0oygukmswolcvorlvcvxafq187frk77qdiyxlkmh8iy1bknywxmxk7nbw7ljg70edoprlemy07ekh3lgyclgsom7w7ljg7wewioxu13svz33gslkwxz2dulb17frkh0r0zt2ectgfpthj1lrpb1gkbtijzrggs0wjz1xy1mju7atjznlwb18a7mvpzw2vs0r8o2gwolg8oy1bknypclgfsmvwpljg70rwiigy1muvokthklj7318a7qcjzlxbbyw0obglznrvzs3h1nedx1rzbtijz3xhu0uui3reeqjwpetd3nedx3rzbtijz72j7wkwir2qslgy7atjtntpbxgdhqb17frko7u8zbgwknju7atjclgdx0jpsmvypfrfc7rwizgekmsyzy1bknywcmgd33czpygdbwgpin2tctgfpthdonqjxrgdbtijzq2j1wudmireznrjp23k3quu3xxfcmv8zt8vs0rjiorlclgfptckolqycygsfqiw7ljg7wjdor2qmqw07ekh3nqyclxdbmczpyxfm7ujobrebmryzw3bknyvbyxamncjot8vs0rjo32wctgfpt3gknjwbmxakqvypf2j38uui3gu1mywpktjmlhyc18a7qojonxbbyw0o1xwzqg07ekh3lq8xmga33czpyxgf0wvz7jlzqu8pfcdfnedcfrzbtijz12jk0wyz720qqkjz73j1qt0318a7qoypy2g38uui3xleqs0oekh3lhpbzrk7mi8ofxdbyw0o1glqqswoucfoluu3xxf7qvwot8vs0ryz7gukmh8iy1bkny8xxxkcnvvpagkuwwdo880qqkjznhh72tfxmxkumowos2ho0s0onrwctgfptchhngyclxkznz0oyxh38uui32l1mujzehdolhybl2a33czpyrfu0evzp2qmqwvzltk72tfxmrafm28z1rfz7qjz3xqctgfpttkbql0318a7q3doggdu0tji7jlzqa8z0cg72tfxmrd7mcw7ljg7wjdor2qmqw07ekh3ljyc8gj7mc87frkm7u0zo2yolkyz3cvorlvc8xfbqb17frko7u8zbgwknju7atjmltpxuxkcnczpyrfuwadotx713svz33gslkwxz2dunvpzwxbbyw0oprl7lgpo3tfqlhvcprzbtijzyxh1wwyi7xl13svzr3j1qj8x12kbtijzggg77u8zw2qems07ekh3lq8xmga33czpy2g3euvm7jlzqjdpathzmuwb1gpsmvjzd2kh0u0z32qqqhy7atj1nlybxrd7lb17frkz0uyi7gubmryzekh3nq8x2gpsmv8plxd1wupow2ectgfptcdqnyvx18a7mo8za2vs0r0ooglmqdjzy1bknydb12kuqxyit8vs0rjibreumju7atjcme8xmga33czpyxgf0tjotxyemuyz3cfqqqyc0jpsmv0p0rjh0qyit2wonr07ekh3ljycbgfcncdog2kh0q8p7x713svzwtjoluu3xxfmmbdo12hbwg0zw2ttqg07ekh3ltvc1rzbtijz12jceqwzqrwkmg07ekh3ng8xxrzbtijz0rgm7lpiw2wuqgfpt3gklhpbz2a7nzjz82vs0rjiory1muyz2cvorlvcbgdkmidoxrfcegdo12lkmsjzy1bknywxcgfcm80odgfb0gjzkxl1mju7atj3my8cvgfml88zq2d7wkpioglctgfpttjhlldb12kcnczpy2hswkdom2wolgfpt3hoqqwbzrkhmz8z1rf38uui32qqquwotthsly8xxgd33czpyxj70uvm7jlzqjwzg3f3qhy3xxf7nzdilrf38uui3gy1mu8pl3a72tfxm2d3nczpyxfb7gvi7jlzqayovcvorlvc2rkbtijzh2kmeudoi2w3mju7atjbnhvb1gpsmv0o12hz0wyio2l1mrpoktjorlvc2gjsmv0ogrgs0gvm7jlzmhyo33korlvc7rdcm88ou2vs0ryoeglzmr8pshh3quu3xxfcmi8ouxgb0uui3xu1la0oekh3lr0b18a7m3ppgxd38uui32qqquwotthsly8xxgd33czpyxj70uvm7jlzmh0ot3bknywc1xffmowodrfuwkpioglctgfpt3gknjwbmxakqvypf2j38uui3xwzqg07ekh3lr0bmgpsmvjzdggo7u8zt2qemsy7atj7mhvbprzbtijzexf70uui3reemsdoehd3mejxxgpsmvdol2gfwjpopx713svzkhh3qhvccgammzpplxbbyw0o0re1mju7atjblkvc18a7qcyif2kk0q0o7jlzqjwpktkkluu3xxfuqijomrkf0e8obgl1mju7atjznyyc0jpsmvvz7gg38uui3rukqa0od3gbnfvc2xd33czpyxgf0jdorru7ldwotcg72tfxmxkumowos2ho0sdmiremmy07ekh3ltvc1rzbtijzggg7ek0oo2loqddpecvorlvc8xfbqb17frkh0wwiy20qqkvok3h7qq8x2gh33czpygfbwudz32w13svzw3k7mtdx8gdsmv8zljg7wupitxybmsvzecvorlvc72kmnbyiljg7wh8zbgyctgfpthdonqjxrgdbtijznggz7tyiw2w3qgfpttjmlqwxqrzbtijzsrg1wu0zwrlolgvo03afnt0318a7q8vpsxgbyw0oy2qclgwpkhholuu3xxfuqijomrkf0e8obgl1mju7atjznyyc0jpsmv0pg2guwkdmirezqsdpt3f1qjycxxfulb17frk1wwyioxybmryzekh3nqycbrdbq1w7ljg70qyit2wonry7atj3mfdxmgpsmvdzngjo0u8ztx713svzuhhknlwb7rjbmczpyrkt0tyii2wtqgfptckolkycxrdbqijzg2j7etfmirebmsdpscfmlhyc18a7qx8zfrkb0uui3xw1myvoy1bknydcwxd1mzppqgd1wg0z880qqkvok3h7qq8x2gh7qxvzt8vs0rjiory1muvom3gzmy0x0jpsmv0pdrg37uui3rukqa0od3gbnf0318a7qovpdxfbyw0o3rlumk8pa3k72tfxm2kbqc8oy2jbyw0o02wclgdpw3kknyyc18a7qcyp8xd1ww0o7x713svz33gslkwxz2dunvpzwxbbyw0oprl7lgpo3tfqlhvcprzbtijzqrkbwtfmiremlgpokhkqquu3xxf7nvyp7xbbyw0ongw7ng07ekh3njwxrrzbtijzu2hc7uui32lbms8p8cvorlvcw2kbmczpyxgf0wvz7jlzmy8p83kfnedxz2azqb17frkm7udiogy1qgfptckoqkwxzxf1q38zljg7wu8omx713svzqhfkluu3xxfuqijomrkf0e8obgl1mju7atjznedxygd33czpy2kc0rdo880qqkvot3gbquu3xxfhmivp32vs0rvzbxu1ma8pa3gknr0318a7mzpp8xd70wdi22qqqg07ekh3ltvc1rzbtijz12jk0wyz720qqkwz7cdfnevc7rjbmczpyxjm0yvm7jlzqu8pfcdfnedcfxfomxw7ljg7wewiq2wolujokcf3le0318a7qcvpm2vs0r0onrw13svzdthhlky3xxf3nzwolxguwwpiirwctgfpttkolky3xxfhmivolgfuwwwo880qqk8patdzmyjxb2fuqi8zt8vs0r0zb2lcna8pl3a3lrjc0jpsmv0pdrdbwg0zq2q3lk0py1bknywcmgd33czpygj37uui3xqbmuwzehholty3xxf1mvjzn2g38uui3gwclgfptcgmljwc12abqc87frkc0wjz880qqk8patdzmyjxb2fuqi8zt8vs0r0zb2lcna8pl3a3lrjc0jpsmv0pdrdbwg0zq2q3lk0py1bknywcmgd33czpy2kcwldztxy13svz33gumtvb0jpsmvpolgfuwypp880qqkdzdthmlh8xxxd3niypfxd7ekppp2wctgfpttd7qq8xygpsmvjzh2kswwdopructgfptck3nt0318a7q28z12ho0svm7jlzqg0i8th3mty3xxfhmzpol2vs0ryz1xl1lgvoy1bknyvb2xfbtijzggg7ekdmireemuwzehdqlljc0jpsmvjz12j1wkdo7jlzquwouchfntfxm2dmnc8zljg70rjieru3lgpo3cvorlvcqgdhmcjzm2vs0r0ov2ekmsy7atjhlkwb0jpsmv0zy2j38uui32qqquwotthsly8xxgd33czpy2kcwldztxy13svz33gumtvb0jpsmvpolgfuwypp880qqkpz23kmnwy3xxfkmc8pq2j3etfmire3qkyzy1bknypb1rdbnv8zljg7wypoirl1nr07ekh3ljycqxabl8jzl2vs0r0zv2eolddpqcvorlvcogdmli8zs2vs0ryoogu13svzu3fzmlpbu2abtijz3gffwypip2qqqh07ekh3nywx1gfsm3woljg70gwinxy13svzkcd72tfxmrjtq8vpnrjtwhdzw20qqk0o23gklh0318a7q28z12ho0svm7jlzmh0oq3jbmtpbz2dulbz0f';
my $soft_ip_opt_passes = '--acle ljg7wk8o12ectgfpthjmnj8xmgf1qb17frk77qdiyxlkmh8ithkcluu3xxf7nvyzs2kmegdoyxlctgfpt3kmljwxfgpsmvjz82j38uui3xleqtyz23bknyycdrkbmv0ot8vs0r8o1guoldyz2cvorlvc3rafqvyzsrg3ekvm7jlzqd0otthknjwbw2kfq1w7ljg7wudo1xwbmujzechqnq0318a7mzpp8xd70wdi22qqqg07ekh3nj8xbrkhmzpzxrko0yvm7jlzmypo7hhontfxmgdtqb17frkuwwjibgl1mju7atjqllwxz2abmczpyxdtwgdotxqemawzekhznk71wyb3r1em3vbbyw0on2yqqkwokthknuwby2k7lb17frk1wgwoygueqajp03ghll0318a7m8jzrxg1wg8z7xutqgfpttd3mu0318a7mcyz1xgu7uui3rezlg07ekh3nj8xbrkhmzpzx2vs0rjibgezqjwpdtd72tfxm2sbnowoljg7wkvir2wbmg8patk72tfxmgfcl3doggkbekdoyguemy8zq3jzmejxxrzbtijzyrgmegdop2e3lgwzekh3lkpbcrk1mxyzm2hfwwvm7jlzqu8pfcdfnedcfxfomxw7ljg70qyitxyzqsypr3gknt0318a7q3yzgxg70tjip2wtqdypy1bknyvbzga3loype2s7wywo880qqkpoe3j3mjjxmgs1q38zt8vs0rjiorlclgfpthdhlh8cygd33czpyxgu0rdi880qqkwpsth7mtfxmgjsm8vogxd7wqdmire3ndpoetdenlwx8gpsqcwmt8vs0rjiorlclgfpt3fknjjbzrj7qzw7ljg70qyitxyzqsypr3gknt0318a7mzppqgd1wg0z880qqkwpsth7mtfxmgscmzvpaxbbyw0oprlemyy7atjzntwx1rjumippt8vs0rwolglctgfpt3honqvcwghfq10ot8vs0r0z3recnju7atjqllvbyxffmodzgggbwtfmiresqryp83bknywbp2kbmb0zgggzwtfmirezqspo23kfnuwb1rdbtijz3gffwhpom2e3ldjpacvorlvc8xkbqb17frk1wu0o7x713svz33gslkwxz2dunvpzwxbbyw0obglznrvzs3h1nedx1rzbtijz8xdm7qvz7jlzmgyzuckorlvcw2kfq3vpm2s37u0z880qqkjzdth1nuwx8xfbqb17frk70wyitxyuqgpoq3k72tfxm2f1q8dog2jmetfmiretqsjp83bknyvbzga3loype2s38uui3xlzquvoucvorlvcvxafq187frkbew8zoxltmju7atjclgdx0jpsmv8pl2g7whppoxu3nju7atj3myvcwrzbtijzggg7ek0oo2loqddpecvorlvcigjkq187frkceq8z72e3qddpqcvorlvcmxaml88zs2kc7ujo7jlzmyposcdmnr8cygsfqiw7ljg7wu0z7x713svzuck3nt0318a7m8ypaxfh0qyokremqh07ekh3nedxqrj7mi8pu2hs0uvm7jlzquwo23g7mtfxmrdbmb0zljg7wh8zoxyemr8i83k3quu3xxfzqovpu2khwu0o7x713svztthknjwbbgdmnx8zt8vs0r8o1guoldyz2cvorlvc7raznbyi82vs0rpiixlkmsyzy1bknyvby2kuq1ppjxbbyw0oirlolapoecf72tfxmrdzq28olxbbyw0o1retqgfptchhnuwc18a7m80odgfb0uui32qqmrpokhh3mevcqgpsmvyzqxj38uui3reemsdoehdzmtfxmgsfq80zljg70qwiqgu13svz0thorlvcz2acl8ypfrfu0r0z880qqkwpstfoljvcc2aolb17frkc0rdo880qqkwpstfoljvcc2a7l3w7ljg70tjiq2ekluy7atj1mtyxc2jbmczpy2gb0edmirekmswo23gknj8xmxk33czpyrf70tji1guolg0odcvorlvcw2kuq2dm12jzwtfmirecnujpfthzmt0blgsolb17frkuww0zwreeqapzkhholuu3xxfcmv8zt8vs0ryobxt1nyy7atj1newbmgf7l3jot8vs0rjiz2wuqgfpttd7qq8xyrjbq8w7ljg7wjdor2qmqw07ekh3lljxlgahm8w7ljg70tjzwgukmkyo03k7qjjxwgfzmb0ogrgswtfmire7mtdpy1bknywcmgd33czpyrfu0evzp2qmqwvzltk72tfxmra7l3donrkc7qyokx713svzkhh3qhvccgammzppl2vs0ryio20qqkdoy1bknyvbmgfhmbdoggsb0uui3xlbmujze3bkny8c3xdmncvzrxdb0gvm7jlzquvzuchmljpb1rkhqb17frko0qvpexu13svzr3gzmy8cqrj7lb17frkh0wwz7guzlt8p0tjeluu3xxf7nvyzs2km7q8p7x713svzwtjoluu3xxf1qcjzlxbbyw0omgyqmju7atjznyyc0jpsmvypfrfc7rwizgekmsyzy1bkny0blxazq8yza2vs0rwoprloqjwpekh3nqycbrzbtijz3gff0y8z12l13svzqchhly8cvgpsmv8pl2gbyw0oerubqhyzy1bknywblgsonzyzs2vs0rdi1xyhmju7atj3meyxwrauqxyiljg7wyvz880qqkwzt3k72tfxmgssqc8zcrfz7tvzy2qqqh07ekh3lhpb72a7lxvp12gbyw0oygukmswolcvorlvcvxafq187frk77qdiyxlkmh8iy1bknywxmxk7nbw7ljg70gdoprlemy07ekh3lypc22kbm187frk1wwyioxybmryzy1bknywccrjbtijzygjz0uui3geomhpoe3d72tfxmxkumowos2ho0s0onrwctgfpt3holjjc12kbq38o1gg38uui3geoljdptcgorlvcmxasq28z1rfu0wyirv713svzwtjoluu3xxfuqijomrkf0e8obgl1mju7atjbmtvcyxamnzdil2vs0r0i7guqqgwpy1bknydb12kuqxyit8vs0rwolglctgfpt3gknjwbmxakqvypf2j38uui3xwzqg07ekh3lgyclgsom7w7ljg7wgdozrlmlgy7atjznt8c8gpsmvjomrgm7u0z880qqkwzt3k72tfxm2jbq8ype2s38uui32l1mujze3bkny0blgdcmzjzrxdbwudmireznrjp23k3quu3xxfcmv8zt8vs0rpiiru3lkjpfhjqllyc0jpsmvyzfggfwkpow2w13svztthmlqycqxfuqivzljg7wrwiegl3qu07ekh3nwycl2abqo87frkc0kvzp2qzqjwoshd72tfxmrd7mcw7ljg7wjdor2qmqw07ekh3nqycbxamn7jzd2kh0u0z32qqqh07ekh3lgyclgsom7w7ljg70yyzix713svzwtjoluu3xxfoncdoggjuetfmirezlk8zd3j1qjyc8gj7q3ypdgg38uui3xlkqkypy1bknywxcxa3nczpyrkf0e8obgl1mju7atjfnevcbrzbtijza2jm7ydor2w3lrpoacvorlvcqgskq10pggju7ryomx713svzdthcmtpbqxjuq3jzhxbbyw0omgyqmju7atjzqj8xrgs1qo87frkk0tjzvx713svzwtjoluu3xxf7nc0orxgu0yyiz2wqmrvoy1bknydb12kuqxyit8vs0r8z7xw1lkyzekh3ljycqxabl8jzlrf38uui3xwzqg07ekh3lgyclgsom7w7ljg70tjox2yznry7atj3mepv1xk33czpyrfu0evzp2qmqwvzltk72tfxmrafm28z1rfz7qjz3xqctgfpttfqll0318a7qvyz1gfu0u8ztxyknayzy1bkny8xxxkcnvvpagkuwwdo880qqkwzt3k72tfxmgabmo87frkm0tyic20qqk0oshdzmtfxmgf7n8ypwggk0uyiwx713svzdthmltvbyxamncjom2sh0uvm7jlzmajoqchqllvb12kclb17frkm7udi1xy1mu8puchqldyc0jpsmv0zy2j38uui3xleqjwz3cfhljycqrjulo8zt8vs0rjzvgueqrjzjcdoqhy3xxf1qippdxd1wkdo880qqkvpehdkntwx18a7m88zs2j7wkwirx713svzwtjoluu3xxfoncdoggjuetfmirezqsdpn3k1qhy3xxfuqi0olrjbwgdmireuqrwp03g7qq8x12k7lb17frkuww0zwreeqapzkhholuu3xxfcmv8zt8vs0rpo0gq1luwoekh3nj8xagd7lb17frko7u8zbgwknju7atjbnhvb1gpsmv0o12hz0wyio2l1mrpoktjorlvc2gjsmv0ogrgs0gvm7jlzmgjp7hjfnty3xxf3n38p32vs0ryoy20qqkyoa3gzquu3xxfuqijomrkf0e8obgl1mju7atjznyyc0jpsmvpz3rkbyw0o02wzqsyp8th3mewbzxasqb17frkuww0zwreeqapzkhholuu3xxfcmv8zt8vs0ryoyre13svztthklgyclxkumippljg7wgdozrlmljwpy1bkny8xxxkcnvvpagkuwwdo880qqkwzt3k72tfxm2d3nv87frkc0syi12lkqky7atjmlq8x32a33czpy2hs0gjz3rlumk8pa3k72tfxmrd7mcw7ljg70gpizxutqddzb3bknydcwrzbtijzqrkbwtfmirebmgpp7tdzmtfxmxkuq08z8xbbyw0ol2wolddzbcvorlvc2rafmb0ogggzwhwibgl3luwobcholuu3xxfbq7wodrfb0uui3xlkmtyzekh3lg8cvgjbm8w7ljg7wewioxu13svz83g7mtwxz2auqivzt8vs0rjo32wctgfpthdonjjxu2k7mc87frk7eqpor2qqqh07ekh3lh0xlxabnxwp32dc7uui3xuolddp0cvorlvcrgdmnzpzxxbbyw0onxu7qjdoehdqlr8v08is';

# device spec differs from board spec since it
# can only contain device information (no board specific parameters,
# like memory interfaces, etc)
my $device_spec = "";
my $soft_ip_c_name = "";
my $accel_name = "";

my $lmem_disable_split_flag = '-no-lms=1';
my $lmem_disable_replication_flag = ' -no-local-mem-replication=1';

# On Windows, always use 64-bit binaries.
# On Linux, always use 64-bit binaries, but via the wrapper shell scripts in "bin".
my $qbindir = ( $^O =~ m/MSWin/ ? 'bin64' : 'bin' );

# For messaging about missing executables
my $exesuffix = ( $^O =~ m/MSWin/ ? '.exe' : '' );

# temporary app data directory
my $tmp_dir = ( $^O =~ m/MSWin/ ? "$ENV{'USERPROFILE'}\\AppData\\Local\\aocl" : "/var/tmp/aocl/$ENV{USERNAME}" );

my $emulator_arch=acl::Env::get_arch();

my $acl_root = acl::Env::sdk_root();
my $installed_bsp_list_file = $acl_root."/installed_packages";
my @installed_packages = ();
my %board_boarddir_map = ();

# Types of IR that we may have
# AOCO sections in shared mode will have names of form:
#    $ACL_CLANG_IR_SECTION_PREFIX . $CLANG_IR_TYPE_SECT_NAME[ir_type]
my $ACL_CLANG_IR_SECTION_PREFIX = ".acl.clang_ir";
my @CLANG_IR_TYPE_SECT_NAME = (
  "fpga64",
  "fpga64be",
  "x86_64-unknown-linux-gnu",
  "x86_64-pc-win32"
);

my $QUARTUS_VERSION = undef; # Saving the output of quartus_sh --version globally to save time.
my $win_longpath_suggest = "\nSUGGESTION: Windows has a 260 limit on the length of a file name (including the full path). The error above *may* have occurred due to the compiler generating files that exceed that limit. Please trim the length of the directory path you ran the compile from and try again.\n\n";

sub mydie(@) {
  print STDERR "Error: ".join("\n",@_)."\n";
  chdir $orig_dir if defined $orig_dir;
  unlink $pkg_file;
  unlink $src_pkg_file;
  exit 1;
}

sub move_to_log { #string, filename ..., logfile
  my $string = shift @_;
  my $logfile= pop @_;
  open(LOG, ">>$logfile") or mydie("Couldn't open $logfile for appending.");
  print LOG $string."\n" if ($string && ($verbose > 1 || $save_temps));
  foreach my $infile (@_) {
    open(TMP, "<$infile") or mydie("Couldn't open $infile for reading.");;
    while(my $l = <TMP>) {
      print LOG $l;
    }
    close TMP;
    unlink $infile;
  }
  close LOG;
}

sub append_to_log { #filename ..., logfile
  my $logfile= pop @_;
  open(LOG, ">>$logfile") or mydie("Couldn't open $logfile for appending.");
  foreach my $infile (@_) {
    open(TMP, "<$infile")  or mydie("Couldn't open $infile for reading.");
    while(my $l = <TMP>) {
      print LOG $l;
    }
    close TMP;
  }
  close LOG;
}

sub move_to_err { #filename ..., logfile
  foreach my $infile (@_) {
    open(ERR, "<$infile");  ## We currently can't guarantee existence of $infile # or mydie("Couldn't open $infile for appending.");
    while(my $l = <ERR>) {
      print STDERR $l;
    }
    close ERR;
    unlink $infile;
  }
}

# checks host OS, returns true for linux, false for windows.
sub isLinuxOS {
    if ($^O eq 'linux') {
      return 1; 
    }
    return 0;
}

# checks for Windows host OS. Returns true if Windows, false if Linux.
# Uses isLinuxOS so OS check is isolated in single function.
sub isWindowsOS {
    if (isLinuxOS()) {
      return 0;
    }
    return 1;
}

# This functions filters output from LLVM's --time-passes
# into the time log. The source log file is modified to not
# contain this output as well.
sub filter_llvm_time_passes {
  my ($logfile) = @_;

  if ($time_passes) {
    open (my $L, '<', $logfile) or mydie("Couldn't open $logfile for reading.");
    my @lines = <$L>;
    close ($L);

    # Look for the specific output pattern that corresponds to the
    # LLVM --time-passes report.
    for (my $i = 0; $i <= $#lines;) {
      my $l = $lines[$i];
      if ($l =~ m/^\s+\.\.\. Pass execution timing report \.\.\.\s+$/) {
        # We are in a --time-passes section.
        my $start_line = $i - 1; # -1 because there's a ===----=== line before that's part of the --time-passes output

        # The end of the section is the SECOND blank line.
        for(my $j = 0; $j < 2; ++$j) {
          for(++$i; $i <= $#lines && $lines[$i] !~ m/^$/; ++$i) {
          }
        }
        my $end_line = $i;

        my @time_passes = splice (@lines, $start_line, $end_line - $start_line + 1);
        print $time_log_fh join ("", @time_passes);

        # Continue processing the rest of the lines, taking into account that
        # a chunk of the array just got removed.
        $i = $start_line;
      }
      else {
        ++$i;
      }
    }

    # Now rewrite the log file without the --time-passes output.
    open ($L, '>', $logfile) or mydie("Couldn't open $logfile for writing.");
    print $L join ("", @lines);
    close ($L);
  }
}

# This is called between system call and check child error so it can 
# NOT do system calls
sub move_to_err_and_log { #String filename ..., logfile
  my $string = shift @_;
  my $logfile = pop @_;
  foreach my $infile (@_) {
    open ERR, "<$infile"  or mydie("Couldn't open $logfile for reading.");
    while(my $l = <ERR>) {
      print STDERR $l;
    }
    close ERR;
    move_to_log($string, $infile, $logfile);
  }
}

# Functions to execute external commands, with various wrapper capabilities:
#   1. Logging
#   2. Time measurement
# Arguments:
#   @_[0] = { 
#       'stdout' => 'filename',   # optional
#       'stderr' => 'filename',   # optional
#       'time' => 0|1,            # optional
#       'time-label' => 'string'  # optional
#     }
#   @_[1..$#@_] = arguments of command to execute
sub mysystem_full($@) {
  my $opts = shift(@_);
  my @cmd = @_;

  my $out = $opts->{'stdout'};
  my $err = $opts->{'stderr'};

  if ($verbose >= 2) {
    print join(' ',@cmd)."\n";
  }

  # Replace STDOUT/STDERR as requested.
  # Save the original handles.
  if($out) {
    open(OLD_STDOUT, ">&STDOUT") or mydie "Couldn't open STDOUT: $!";
    open(STDOUT, ">$out") or mydie "Couldn't redirect STDOUT to $out: $!";
    $| = 1;
  }
  if($err) {
    open(OLD_STDERR, ">&STDERR") or mydie "Couldn't open STDERR: $!";
    open(STDERR, ">$err") or mydie "Couldn't redirect STDERR to $err: $!";
    select(STDERR);
    $| = 1;
    select(STDOUT);
  }

  # Run the command.
  my $start_time = time();
  system(@cmd);
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
  if ($time_log_fh && $opts->{'time'}) {
    my $time_label = $opts->{'time-label'};
    if (!$time_label) {
      # Just use the command as the label.
      $time_label = join(' ',@cmd);
    }

    log_time ($time_label, $end_time - $start_time);
  }
  return $?
}

sub mysystem_redirect($@) {
  # Run command, but redirect standard output to $outfile.
  my ($outfile,@cmd) = @_;
  return mysystem_full ({'stdout' => $outfile}, @cmd);
}

sub mysystem(@) {
  return mysystem_redirect('',@_);
}

sub hard_routing_error_code($@)
{
  my $error_string = shift @_;
  if( $error_string =~ /Error\s*\(170113\):/ ) {
    return 1;
  }
  return 0;
}

sub kernel_fit_error($@)
{
  my $error_string = shift @_;
  if( $error_string =~ /Error\s*\(11802\):/ ) {
    return 1;
  }
  return 0;
}

sub win_longpath_error_quartus($@)
{
  my $error_string = shift @_;
  if( $error_string =~ /Error\s*\(14989\):/ ) {
    return 1;
  }
  if( $error_string =~ /Error\s*\(19104\):/ ) {
    return 1;
  }
  if( $error_string =~ /Error\s*\(332000\):/ ) {
    return 1;
  }
  return 0;
}

sub win_longpath_error_llc($@)
{
  my $error_string = shift @_;
  if( $error_string =~ /Error:\s*Could not open file/ ) {
    return 1;
  }
  return 0;
}

sub hard_routing_error($@)
 { #filename
     my $infile = shift @_;
     open(ERR, "<$infile");  ## if there is no $infile, we just return 0;
     while( <ERR> ) {
       if( hard_routing_error_code( $_ ) ) {
         return 1;
       }
     }
     close ERR;
     return 0;
 }

sub print_bsp_msgs($@)
 { 
     my $infile = shift @_;
     open(IN, "<$infile") or mydie("Failed to open $infile");
     while( <IN> ) {
       # E.g. Error: BSP_MSG: This is an error message from the BSP
       if( $_ =~ /BSP_MSG:/ ){
         my $filtered_line = $_;
         $filtered_line =~ s/BSP_MSG: *//g;
         if( $filtered_line =~ /^ *Error/ ) {
           print STDERR "$filtered_line";
         } elsif ( $filtered_line =~ /^ *Critical Warning/ ) {
           print STDOUT "$filtered_line";
         } elsif ( $filtered_line =~ /^ *Warning/ && $verbose > 0) {
           print STDOUT "$filtered_line";
         } elsif ( $verbose > 1) {
           print STDOUT "$filtered_line";
         }
       }
     }
     close IN;
 }

sub print_quartus_errors($@)
{ #filename
  my $infile = shift @_;
  my $flag_recomendation = shift @_;
  my $win_longpath_flag = 0;
  
  open(ERR, "<$infile") or mydie("Failed to open $infile");
  while( my $line = <ERR> ) {
    if( $line =~ /^Error/ ) {
      if( hard_routing_error_code( $line ) && $flag_recomendation ) {
        print STDERR "Error: Kernel fit error, recommend using --high-effort.\n";
      }
      if( kernel_fit_error( $line ) ) {
        mydie("Cannot fit kernel(s) on device");
      }
      elsif ( win_longpath_error_quartus( $line ) ) {
        $win_longpath_flag = 1;
        print $line;
      }
      elsif ($line =~ /Error\s*(?:\(\d+\))?:/) {
        print $line;
      }
    }
    if( $line =~ /Path name is too long/ ) {
      $win_longpath_flag = 1;
      print $line;
    }
  }
  close ERR;
  print $win_longpath_suggest if ($win_longpath_flag and isWindowsOS());
  mydie("Compiler Error, not able to generate hardware\n");
}

sub log_time($$) {
  my ($label, $time) = @_;
  if ($time_log_fh) {
    printf ($time_log_fh "[time] %s ran in %ds\n", $label, $time);
  }
}

sub save_pkg_section($$$) {
   my ($pkg,$section,$value) = @_;
   # The temporary file should be in the compiler work directory.
   # The work directory has already been created.
   my $file = $work_dir.'/value.txt';
   open(VALUE,">$file") or mydie("Can't write to $file: $!");
   binmode(VALUE);
   print VALUE $value;
   close VALUE;
   $pkg->set_file($section,$file)
       or mydie("Can't save value into package file: $acl::Pkg::error\n");
   unlink $file;
}

sub save_vfabric_files_to_pkg($$$$$) {
  my ($pkg, $var_id, $vfab_lib_path, $work_dir, $board_variant) = @_;
  if (!-f $vfab_lib_path."/var".$var_id.".fpga.bin" ) {
    mydie("Cannot find Rapid Prototyping programming file.");
  }

  if (!-f $vfab_lib_path."/sys_description.txt" ) {
    mydie("Cannot find Rapid Prototyping system description.");
  }

  if (!-f $work_dir."/vfabric_settings.bin" ) {
    mydie("Cannot find Rapid Prototyping configuration settings.");
  }

  # add the complete vfabric configuration file to the package
  $pkg->set_file('.acl.vfabric', $work_dir."/vfabric_settings.bin")
      or mydie("Can't save Rapid Prototyping configuration file into package file: $acl::Pkg::error\n");

  $pkg->set_file('.acl.fpga.bin', $vfab_lib_path."/var".$var_id.".fpga.bin" )
      or mydie("Can't save FPGA programming file into package file: $acl::Pkg::error\n");

  #Issue an error if autodiscovery string is larger than 4k (only for version < 15.1).
  my $acl_board_hw_path= get_acl_board_hw_path($board_variant);
  my $board_spec_xml = find_board_spec($acl_board_hw_path);
  my $bsp_version = acl::Env::aocl_boardspec( "$board_spec_xml", "version");
  if( (-s $vfab_lib_path."/sys_description.txt" > 4096) && ($bsp_version < 15.1) ) {
    mydie("System integrator FAILED.\nThe autodiscovery string cannot be more than 4096 bytes\n");
  }
  $pkg->set_file('.acl.autodiscovery', $vfab_lib_path."/sys_description.txt")
      or mydie("Can't save system description into package file: $acl::Pkg::error\n");

  # Include the acl_quartus_report.txt file if it exists
  my $acl_quartus_report = $vfab_lib_path."/var".$var_id.".acl_quartus_report.txt";
  if ( -f $acl_quartus_report ) {
    $pkg->set_file('.acl.quartus_report',$acl_quartus_report)
       or mydie("Can't save Quartus report file $acl_quartus_report into package file: $acl::Pkg::error\n");
  }      
}

sub save_profiling_xml($$) {
  my ($pkg,$basename) = @_;
  # Save the profile XML file in the aocx
  $pkg->add_file('.acl.profiler.xml',"$basename.bc.profiler.xml")
      or mydie("Can't save profiler XML $basename.bc.profiler.xml into package file: $acl::Pkg::error\n");
}

# Make sure the board specification file exists. Return directory of board_spec.xml
sub find_board_spec {
  my ($acl_board_hw_path) = @_;
  my ($board_spec_xml) = acl::File::simple_glob( $acl_board_hw_path."/board_spec.xml" );
  my $xml_error_msg = "Cannot find Board specification!\n*** No board specification (*.xml) file inside ".$acl_board_hw_path.". ***\n" ;
  if ( $device_spec ne "" ) {
    my $full_path =  acl::File::abs_path( $device_spec );
    $board_spec_xml = $full_path;
    $xml_error_msg = "Cannot find Device Specification!\n*** device file ".$board_spec_xml." not found.***\n";
  }
  -f $board_spec_xml or mydie( $xml_error_msg );
  return $board_spec_xml;
}

# Do setup checks:
sub check_env {
  my ($board_variant,$bsp_flow_name) = @_;

  if ($do_env_check) {
    # 1. Is clang on the path?
    mydie ("$prog: The Intel(R) FPGA SDK for OpenCL(TM) compiler front end (aocl-clang$exesuffix) can not be found")  unless -x $clang_exe.$exesuffix; 
    # Do we have a license?
    my $clang_output = `$clang_exe --version 2>&1`;
    chomp $clang_output;
    if ($clang_output =~ /Could not acquire OpenCL SDK license/ ) {
      mydie("$prog: Can't find a valid license for the Intel(R) FPGA SDK for OpenCL(TM)\n");
    }
    if ($clang_output !~ /Intel\(R\) FPGA SDK for OpenCL\(TM\), Version/ ) {
      print "$prog: Clang version: $clang_output\n" if $verbose||$regtest_mode;
      if ($^O !~ m/MSWin/ and ($verbose||$regtest_mode)) {
        my $ld_library_path="$ENV{'LD_LIBRARY_PATH'}";
        print "LD_LIBRARY_PATH is : $ld_library_path\n";
        foreach my $lib_dir (split (':', $ld_library_path)) {
          if( $lib_dir =~ /dspba/){
            if (! -d $lib_dir ){
              print "The library path: $lib_dir does not exist\n";
            }
          }
        }
      }
      my $failure_cause = "The cause of failure cannot be determined. Run executable manually and watch for error messages.\n";
      # Common cause on linux is an old libstdc++ library. Check for this here.
      if ($^O !~ m/MSWin/) {
        my $clang_err_out = `$clang_exe 2>&1 >/dev/null`;
        if ($clang_err_out =~ m!GLIBCXX_!) {
          $failure_cause = "Cause: Available libstdc++ library is too old. You're probably using an unsupported version of Linux OS. " .
                           "A quick work-around for this is to get latest version of gcc (at least 4.4) and do:\n" .
                           "  export LD_LIBRARY_PATH=<gcc_path>/lib64:\$LD_LIBRARY_PATH\n";
        }
      }
      mydie("$prog: Executable $clang_exe exists but is not working!\n\n$failure_cause");
    }

    # 2. Is /opt/llc/system_integrator on the path?
    mydie ("$prog: The Intel(R) FPGA SDK for OpenCL(TM) compiler front end (aocl-opt$exesuffix) can not be found")  unless -x $opt_exe.$exesuffix;
    my $opt_out = `$opt_exe  --version 2>&1`;
    chomp $opt_out; 
    if ($opt_out !~ /Intel\(R\) FPGA SDK for OpenCL\(TM\), Version/ ) {
      mydie("$prog: Can't find a working version of executable (aocl-opt$exesuffix) for the Intel(R) FPGA SDK for OpenCL(TM)\n");
    }
    mydie ("$prog: The Intel(R) FPGA SDK for OpenCL(TM) compiler front end (aocl-llc$exesuffix) can not be found")  unless -x $llc_exe.$exesuffix; 
    my $llc_out = `$llc_exe --version`;
    chomp $llc_out; 
    if ($llc_out !~ /Intel\(R\) FPGA SDK for OpenCL\(TM\), Version/ ) {
      mydie("$prog: Can't find a working version of executable (aocl-llc$exesuffix) for the Intel(R) FPGA SDK for OpenCL(TM)\n");
    }
    mydie ("$prog: The Intel(R) FPGA SDK for OpenCL(TM) compiler front end (system_integrator$exesuffix) can not be found")  unless -x $sysinteg_exe.$exesuffix; 
    my $system_integ = `$sysinteg_exe --help`;
    chomp $system_integ;
    if ($system_integ !~ /system_integrator - Create complete OpenCL system with kernels and a target board/ ) {
      mydie("$prog: Can't find a working version of executable (system_integrator$exesuffix) for the Intel(R) FPGA SDK for OpenCL(TM)\n");
    }
  }

  my %q_info;
  if (not $standalone)
  {
    # 3. Is Quartus on the path?
    $ENV{QUARTUS_OPENCL_SDK}=1; #Tell Quartus that we are OpenCL
    my $q_out = `quartus_sh --version`;
    $QUARTUS_VERSION = $q_out;

    chomp $q_out;
    if ($q_out eq "") {
      print STDERR "$prog: Quartus is not on the path!\n";
      print STDERR "$prog: Is it installed on your system and quartus bin directory added to PATH environment variable?\n";
      exit 1;
    }

    # 4. Is it right Quartus version?
    my $q_ok = 0;
    $q_info{version} = "";
    $q_info{pro} = 0;
    $q_info{prime} = 0;
    $q_info{internal} = 0;
    $q_info{site} = '';
    my $req_qversion_str = exists($ENV{ACL_ACDS_VERSION_OVERRIDE}) ? $ENV{ACL_ACDS_VERSION_OVERRIDE} : "17.1.0";
    my $req_qversion = acl::Env::get_quartus_version($req_qversion_str);

    foreach my $line (split ('\n', $q_out)) {
#      if ($line =~ /64-Bit/) {
#        $q_ok += 1;
#      }
      # With QXP flow should be compatible with future versions

      # Do version check.
      my ($qversion_str) = ($line =~ m/Version (\S+)/);
      $q_info{version} = acl::Env::get_quartus_version($qversion_str);
      if(acl::Env::are_quartus_versions_compatible($req_qversion, $q_info{version})) {
        $q_ok++;
      }

      # check if Internal version
      if ($line =~ /Internal/) {
        $q_info{internal}++;
      }

      # check which site it is from
      if ($line =~ m/\s+([A-Z][A-Z])\s+/) {
        $q_info{site} = $1;
      }

      # Need this to bypass version check for internal testing with ACDS 15.0.
      if ($line =~ /Prime/) {
        $q_info{prime}++;
      }
      if ($line =~ /Pro Edition/) {
        $q_info{pro}++;
        $is_pro_mode = 1;
      }
    }
    if ($do_env_check && $q_ok != 1) {
      print STDERR "$prog: This release of the Intel(R) FPGA SDK for OpenCL(TM) requires ACDS Version $req_qversion_str (64-bit).";
      print STDERR " However, the following version was found: \n$q_out\n";
      exit 1;
    }
  
    # 5. Is it Quartus Prime Standard or Pro device?
    my $platform_type = undef;
    my $acl_board_hw_path= get_acl_board_hw_path($board_variant);
    my $board_spec_xml = find_board_spec($acl_board_hw_path);
    if( ! $bsp_flow_name ) {
      $bsp_flow_name = ":".acl::Env::aocl_boardspec( "$board_spec_xml", "defaultname" );
    }
    $platform_type = acl::Env::aocl_boardspec( "$board_spec_xml", "automigrate_type".$bsp_flow_name);
    ( $platform_type !~ /error/ ) or mydie("BSP compile-flow $bsp_flow_name not found\n");

    if ($do_env_check) {
      if (($q_info{prime} == 1) && ($q_info{pro} != 1) && ($platform_type =~ /^a10/ || $platform_type =~ /^s10/)) {
        print STDERR "$prog: This release of Intel(R) FPGA SDK for OpenCL(TM) on A10/S10 requires Quartus Prime Pro Edition.";
        print STDERR " However, the following version was found: \n$q_out\n";
        exit 1;
      }
      if (($q_info{prime} == 1) && ($q_info{pro} == 1) && ($platform_type !~ /^a10/ && $platform_type !~ /^s10/)) {
        print STDERR "$prog: Use Quartus Prime Standard Edition for non A10/S10 devices.";
        print STDERR " Current Quartus Version is: \n$q_out\n";
        exit 1;
      }
    }
  }
  
  # If here, everything checks out fine.
  print "$prog: Environment checks are completed successfully.\n" if $verbose;
  return %q_info;
}

sub extract_atoms_from_postfit_netlist($$$$) {
  my ($base,$location,$atom,$bsp_flow_name) = @_;

   # Grab DSP location constraints from specified Quartus compile directory  
    my $script_abs_path = acl::File::abs_path( acl::Env::sdk_root()."/ip/board/bsp/extract_atom_locations_from_postfit_netlist.tcl"); 

    # Pre-process relativ or absolute location
    my $location_dir = '';
    if (substr($location,0,1) eq '/') {
      # Path is already absolute
      $location_dir = $location;
    } else {
      # Path is currently relative
      $location_dir = acl::File::abs_path("../$location");
    }
      
    # Error out if reference compile directory not found
    if (! -d $location_dir) {
      mydie("Directory '$location' for $atom locations does not exist!\n");
    }

    # Error out if reference compile board target does not match
    my $current_board = ::acl::Env::aocl_boardspec( ".", "name");
    my $reference_board = ::acl::Env::aocl_boardspec( $location_dir, "name");
    if ($current_board ne $reference_board) {
      mydie("Reference compile board name '$reference_board' and current compile board name '$current_board' do not match!\n");
    };

    my $project = ::acl::Env::aocl_boardspec( ".", "project".$bsp_flow_name);
    my $revision = ::acl::Env::aocl_boardspec( ".", "revision".$bsp_flow_name);
    ( $project.$revision !~ /error/ ) or mydie("BSP compile-flow $bsp_flow_name not found\n");
    chomp $revision;
    if (defined $ENV{ACL_QSH_REVISION})
    {
      # Environment variable ACL_QSH_REVISION can be used
      # replace default revision (internal use only).  
      $revision = $ENV{ACL_QSH_REVISION};
    }
    my $current_compile = acl::File::mybasename($location);
    my $cmd = "cd $location_dir;quartus_cdb -t $script_abs_path $atom $current_compile $base $project $revision;cd $work_dir";
    print "$prog: Extracting $atom locations from '$location' compile directory (from '$revision' revision)\n";
    my $locationoutput_full = `$cmd`;

    # Error out if project cannot be opened   
    (my $locationoutput_projecterror) = $locationoutput_full =~ /(Error\: ERROR\: Project does not exist.*)/s;
    if ($locationoutput_projecterror) {
      mydie("Project '$project' and revision '$revision' in directory '$location' does not exist!\n");
    }
 
    # Error out if atom netlist cannot be read
    (my $locationoutput_netlisterror) = $locationoutput_full =~ /(Error\: ERROR\: Cannot read atom netlist.*)/s;
    if ($locationoutput_netlisterror) {
      mydie("Cannot read atom netlist from revision '$revision' in directory '$location'!\n");
    }

    # Add location constraints to current Quartus compile directory
    (my $locationoutput) = $locationoutput_full =~ /(\# $atom locations.*)\# $atom locations END/s;
    my @designs = acl::File::simple_glob( "*.qsf" );
    $#designs > -1 or mydie ("Internal Compiler Error. $atom location argument was passed but could not find any qsf files\n");
    foreach (@designs) {
      my $qsf = $_;
      open(my $fd, ">>$qsf");
      print $fd "\n";
      print $fd $locationoutput;
      close($fd);
    }
}


sub get_acl_board_hw_path {
  my $bv = shift @_;
  my ($result) = acl::Env::board_hw_path($bv);
  return $result;
}


sub remove_named_files {
    foreach my $fname (@_) {
      acl::File::remove_tree( $fname, { verbose => ($verbose == 1 ? 0 : $verbose), dry_run => 0 } )
         or mydie("Cannot remove intermediate files under directory $fname: $acl::File::error\n");
    }
}

sub remove_intermediate_files($$) {
   my ($dir,$exceptfile) = @_;
   my $thedir = "$dir/.";
   my $thisdir = "$dir/..";
   my %is_exception = (
      $exceptfile => 1,
      "$dir/." => 1,
      "$dir/.." => 1,
   );
   foreach my $file ( acl::File::simple_glob( "$dir/*", { all => 1 } ) ) {
      if ( $is_exception{$file} ) {
         next;
      }
      if ( $file =~ m/\.aclx$/ ) {
         next if $exceptfile eq acl::File::abs_path($file);
      }
      acl::File::remove_tree( $file, { verbose => $verbose, dry_run => 0 } )
         or mydie("Cannot remove intermediate files under directory $dir: $acl::File::error\n");
   }
   # If output file is outside the intermediate dir, then can remove the intermediate dir
   my $files_remain = 0;
   foreach my $file ( acl::File::simple_glob( "$dir/*", { all => 1 } ) ) {
      next if $file eq "$dir/.";
      next if $file eq "$dir/..";
      $files_remain = 1;
      last;
   }
   unless ( $files_remain ) { rmdir $dir; }
}

sub get_area_percent_estimates {
  # Get utilization numbers (in percent) from area.json.
  # The file must exist when this function is called.

  open my $area_json, '<', $work_dir."/area.json";
  my $util = 0;
  my $les = 0;
  my $ffs = 0;
  my $rams = 0;
  my $dsps = 0;

  while (my $json_line = <$area_json>) {
    if ($json_line =~ m/\[([.\d]+), ([.\d]+), ([.\d]+), ([.\d]+), ([.\d]+)\]/) {
      # Round all percentage values to the nearest whole number.
      $util = int($1 + 0.5);
      $les = int($2 + 0.5);
      $ffs = int($3 + 0.5);
      $rams = int($4 + 0.5);
      $dsps = int($5 + 0.5);
      last;
    }
  }
  close $area_json;

  return ($util, $les, $ffs, $rams, $dsps);
}

# Copied from i++.pl
sub device_get_family_no_normalization {  # DSPBA needs the original Quartus format
    my $local_start = time();
    my $qii_family_device = shift;
    my $family_from_quartus = `quartus_sh --tcl_eval get_part_info -family $qii_family_device`;
    # Return only what's between the braces, without the braces
    ($family_from_quartus) = ($family_from_quartus =~ /\{(.*)\}/);
    chomp $family_from_quartus;
    log_time ('Get device family', time() - $local_start) if ($time_log_fh);
    return $family_from_quartus;
}

sub create_reporting_tool {
  my $fileJSON = shift;
  my $base = shift;
  my $all_aoc_args = shift;
  my $board_variant = shift;
  my $disabled_lmem_repl = shift;
  my $devicemodel = shift;
  my $devicefamily = shift;

  # Need to call board_name() before modifying $/
  my ($board_name) = acl::Env::board_name();

  local $/ = undef;

  acl::File::make_path("$work_dir/reports") or return;
  acl::Report::copy_files($work_dir) or return;

  # Collect information for infoJSON, and print it to the report
  my $acl_version = "17.1.0 Build 590";
  (my $mProg = $prog) =~ s/#//g;
  my $mTime = localtime;
  my ($quartus_version) = $QUARTUS_VERSION =~ /Version (.* Build \d*)/;
  my $infoJSON = "{\"name\":\"Info\",\"rows\":[\n";
  $infoJSON .= "{\"name\":\"Project Name\",\"data\":[\"".escape_string($base)."\"],\"classes\":[\"info-table\"]},\n";
  $infoJSON .= "{\"name\":\"Target Family, Device, Board\",\"data\":[\"$devicefamily, $devicemodel, ".escape_string("$board_name:$board_variant")."\"]},\n";
  $infoJSON .= "{\"name\":\"AOC Version\",\"data\":[\"$acl_version\"]},\n";
  $infoJSON .= "{\"name\":\"Quartus Version\",\"data\":[\"$quartus_version\"]},\n";
  $infoJSON .= "{\"name\":\"Command\",\"data\":[\"$mProg ".escape_string($all_aoc_args)."\"]},\n";
  $infoJSON .= "{\"name\":\"Reports Generated At\", \"data\":[\"$mTime\"]}\n";
  $infoJSON .= "]}";

  # warningsJSON
  my $first = 1;
  my $warningsJSON = "{\"rows\":[\n";
  if ($disabled_lmem_repl) {
        $warningsJSON .= "," unless $first; $first = 0;
    $warningsJSON .= "{\"name\":\"Local memory replication disabled\"";
    $warningsJSON .= ", \"data\":[1]";
    $warningsJSON .= ", \"details\":[\"Local memory replication was disabled due to estimated overutilization of RAM blocks.\"]";
        $warningsJSON .= "}\n";
  }
  if (open (my $file, "<iteration.tmp.err")) {
    my @lines = split("\n", <$file>);
    for my $line (@lines) {
      my $search_string = "Compiler Warning: "; 
      if ($line =~ m/$search_string/) {
        my $start_index = index($line, $search_string);
        $line =~ s/\n|\r//g;
        $warningsJSON .= "," unless $first; $first = 0;
        $warningsJSON .= "{\"name\":\"".escape_string(substr($line, $start_index + 18, $start_index + 82))."...\"\n";
        $warningsJSON .= ",\"details\":[\"".escape_string($line)."\"]";
        $warningsJSON .= "}\n";
      }
    }
  }
  $warningsJSON .= "]}";

  # create the area_src json file
  acl::Report::parse_to_get_area_src($work_dir);
  # List of JSON files to print to report_data.js
  my @json_files = ("area", "area_src", "mav", "lmv", "loops", "summary");
  open (my $report, ">$work_dir/reports/lib/report_data.js") or return;

  acl::Report::create_json_file_or_print_to_report($report, "info", $infoJSON, \@json_files);
  acl::Report::create_json_file_or_print_to_report($report, "warnings", $warningsJSON, \@json_files);

  acl::Report::print_json_files_to_report($report, \@json_files);

  print $report $fileJSON;
  close($report);

  # create empty verification data file to avoid browser console error
  open (my $verif_report, ">$work_dir/reports/lib/verification_data.js") or return;
  print $verif_report "";
  close($verif_report);

  if ($pipeline_viewer) {
    acl::Report::create_pipeline_viewer($work_dir, "kernel_hdl", $verbose);
  }
}

sub create_system {
  my ($base,$work_dir,$src,$obj,$board_variant, $using_default_board,$all_aoc_args,$bsp_flow_name,$input_dir) = @_;
  
  my $pkg_file_final = $obj;
  (my $src_pkg_file_final = $obj) =~ s/aoco/source/;
  $pkg_file = $pkg_file_final.".tmp";
  $src_pkg_file = $src_pkg_file_final.".tmp";
  $fulllog = "$base.log"; #definition moved to global space
  my $run_copy_skel = 1;
  my $run_copy_ip = 1;
  my $run_clang = 1;
  my $run_opt = 1;
  my $run_verilog_gen = 1;
  my $run_opt_vfabric = 0;
  my $run_vfabric_cfg_gen = 0;
  my $files;
  my $fileJSON;
  my @move_files = ();
  my @save_files = ();
  if ($incremental) {
    push (@save_files, 'qdb');
    push (@save_files, 'current_partitions.txt');
    push (@save_files, 'new_floorplan.txt');
    push (@save_files, 'io_loc.loc');
    push (@save_files, 'partition.*.qdb');
    push (@save_files, 'prev');
    push (@save_files, 'soft_regions.txt');
    push (@move_files, ('*.bc.xml', 'reports', 'kernel_hdl', $marker_file));
  }
  my $finalize = sub {
     unlink( $pkg_file_final ) if -f $pkg_file_final;
     unlink( $src_pkg_file_final ) if -f $src_pkg_file_final;
     rename( $pkg_file, $pkg_file_final )
         or mydie("Can't rename $pkg_file to $pkg_file_final: $!");
     rename( $src_pkg_file, $src_pkg_file_final ) if -f $src_pkg_file;
     chdir $orig_dir or mydie("Can't change back into directory $orig_dir: $!");
  };

  if ( $parse_only || $opt_only || $verilog_gen_only || ($vfabric_flow && !$generate_vfabric) || $emulator_flow ) {
    $run_copy_ip = 0;
    $run_copy_skel = 0;
  }

  if ( $accel_gen_flow ) {
    $run_copy_skel = 0;
  }

  if ($vfabric_flow) {
    $run_opt = 0;
    $run_opt_vfabric = 1;
    $run_vfabric_cfg_gen = 1;
  }

  my $stage1_start_time = time();
  #Create the new direcory verbatim, then rewrite it to not contain spaces
  $work_dir = $work_dir;
  # If there exists a file with the same name as work_dir
  if (-e $work_dir and -f $work_dir) {
    mydie("Can't create project directory $work_dir because file with the same name exists\n");
  }
  #If the work_dir exists, check whether it was created by us
  if (-e $work_dir and -d $work_dir) {
  # If the marker file exists, this was created by us
  # Cleaning up the whole project directory to avoid conflict with previous compiles. This behaviour should change for incremental compilation.
    if (-e "$work_dir/$marker_file" and -f "$work_dir/$marker_file") {
      print "$prog: Cleaning up existing temporary directory $work_dir\n" if ($verbose >= 2);

      if ($incremental && !$input_dir) {
        $acl::Incremental::warning = "$prog: Found existing directory $work_dir, basing incremental compile off this directory.\n";
        print $acl::Incremental::warning if ($verbose);
        $input_dir = $work_dir;
      }

      # If incremental, copy over all incremental files before removing anything (in case of failure or force stop)
      if ($incremental && acl::File::abs_path($input_dir) eq acl::File::abs_path($work_dir)) {
        # Check if prev directory exists and that the marker file exists inside it. The marker file is added after all the necessary
        # previous files are copied over. This indicates that we have a valid set of previous files. The prev directory should automatically
        # be removed after a successful compile, so this directory should only be left over in the case where an incremental compile has failed
        # If an incremental compile has failed, then we should keep the contents of this directory since the kernel_hdl and .bc.xml file in the project 
        # directory may have been already been overwritten
        $input_dir = "$work_dir/prev";
        if (! -e $input_dir || ! -d $input_dir || ! -e "$input_dir/$marker_file") {
          acl::File::make_path($input_dir) or mydie("Can't create temporary directory $input_dir: $!");
          foreach my $reg (@move_files) {
            foreach my $f_match ( acl::File::simple_glob( "$work_dir/$reg") ) {
              my $file_base = acl::File::mybasename($f_match);
              acl::File::copy_tree( $f_match, "$input_dir/" );
            }
          }
        }
      }

      foreach my $file ( acl::File::simple_glob( "$work_dir/*", { all => 1 } ) ) {
        if ( $file eq "$work_dir/." or $file eq "$work_dir/.." or $file eq "$work_dir/$marker_file" ) {
          next;
        }
        my $next_check = undef;
        foreach my $reg (@save_files) {
          if ( $file =~ m/$reg/ ) { $next_check = 1; last; }
        }
        # if the file matches one of the regexps, skip its removal
        if( defined $next_check ) { next; }

        acl::File::remove_tree( $file )
          or mydie("Cannot remove files under temporary directory $work_dir: $!\n");
      }
    } else {
      mydie("Please rename the existing directory $work_dir to avoid name conflict with project directory\n");
    }
  }

  acl::File::make_path($work_dir) or mydie("Can't create temporary directory $work_dir: $!");
  if ($input_dir ne '' && $input_dir ne "$work_dir/prev") {
    foreach my $reg (@save_files) {
      foreach my $f_match ( acl::File::simple_glob( "$input_dir/$reg") ) {
        my $file_base = acl::File::mybasename($f_match);
        acl::File::copy_tree( $f_match, $work_dir."/" );
      }
    }
    $input_dir = acl::File::abs_path("$input_dir");
  }

  # Create a marker file
  my @cmd = isWindowsOS() ? ("type nul > $work_dir/$marker_file"):("touch", "$work_dir/$marker_file");
  mysystem_full({}, @cmd);
  # First, try to delete the log file
  if (!unlink "$work_dir/$fulllog") {
    # If that fails, just try to erase the existing log
    open(LOG, ">$work_dir/$fulllog") or mydie("Couldn't open $work_dir/$fulllog for writing.");
    close(LOG);
  }
  open(my $TMPOUT, ">$work_dir/$fulllog") or mydie ("Couldn't open $work_dir/$fulllog to log version information.");
  print $TMPOUT "Compiler Command: " . $prog . " " . $all_aoc_args . "\n";
  if (defined $acl::Incremental::warning) {
    print $TMPOUT $acl::Incremental::warning;
  }
  if ($regtest_mode){
      version ($TMPOUT);
  }
  close($TMPOUT);
  my $acl_board_hw_path= get_acl_board_hw_path($board_variant);

  # If just packaging an HDL library component, call 'aocl library' and be done with it.
  if ($hdl_comp_pkg_flow) {
    print "$prog: Packaging HDL component for library inclusion\n" if $verbose||$report;
    $return_status = mysystem_full(
        {'stdout' => "$work_dir/aocl_libedit.log", 
         'stderr' => "$work_dir/aocl_libedit.err",
         'time' => 1, 'time-label' => 'aocl library'},
        "$aocl_libedit_exe -c \"$absolute_srcfile\" -o \"$output_file\"");
    move_to_err_and_log("!========== [aocl library] ==========", "$work_dir/aocl_libedit.log", "$work_dir/$fulllog"); 
    append_to_log("$work_dir/aocl_libedit.err", "$work_dir/$fulllog");
    move_to_err("$work_dir/aocl_libedit.err");
    $return_status == 0 or mydie("Packing of HDL component FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
    return $return_status;
  }
  
  # Make sure the board specification file exists. This is needed by multiple stages of the compile.
  my $board_spec_xml = find_board_spec($acl_board_hw_path);
  my $llvm_board_option = "-board $board_spec_xml";   # To be passed to LLVM executables.
  my $llvm_efi_option = (defined $absolute_efispec_file ? "-efi $absolute_efispec_file" : ""); # To be passed to LLVM executables
  my $llvm_profilerconf_option = (defined $absolute_profilerconf_file ? "-profile-config $absolute_profilerconf_file" : ""); # To be passed to LLVM executables
  my $llvm_library_option = ($#resolved_lib_files > -1 ? join (' -libfile ', (undef, @resolved_lib_files)) : "");
  
  if (!$accel_gen_flow && !$soft_ip_c_flow) {
    my $default_text;
    if ($using_default_board) {
       $default_text = "default ";
    } else {
       $default_text = "";
    }
    print "$prog: Selected ${default_text}target board $board_variant\n" if $verbose||$report;
  }

  if(defined $absolute_efispec_file) {
    print "$prog: Selected EFI spec $absolute_efispec_file\n" if $verbose||$report;
  }

  if(defined $absolute_profilerconf_file) {
    print "$prog: Selected profiler conf $absolute_profilerconf_file\n" if $verbose||$report;
  }

  if ( $run_copy_skel ) {
    # Copy board skeleton, unconditionally.
    # Later steps update .qsf and .sopc in place.
    # You *will* get SOPC generation failures because of double-add of same
    # interface unless you get a fresh .sopc here.
    acl::File::copy_tree( $acl_board_hw_path."/*", $work_dir )
      or mydie("Can't copy Board template files: $acl::File::error");
    map { acl::File::make_writable($_) } (
      acl::File::simple_glob( "$work_dir/*.qsf" ),
      acl::File::simple_glob( "$work_dir/*.sopc" ) );
  }

  if ( $run_copy_ip ) {
    # Rather than copy ip files from the SDK root to the kernel directory, 
    # generate an opencl.ipx file to point Qsys to hw.tcl components in 
    # the IP in the SDK root when generating the system.
    my $opencl_ipx = "$work_dir/opencl.ipx";
    open(my $fh, '>', $opencl_ipx) or die "Cannot open file '$opencl_ipx' $!";
    print $fh '<?xml version="1.0" encoding="UTF-8"?>
<library>
 <path path="${INTELFPGAOCLSDKROOT}/ip/*" />
</library>
';
    close $fh;

    # Also generate an assignment in the .qsf pointing to this IP.
    # We need to do this because not all the hdl files required by synthesis
    # are necessarily in the hw.tcl (i.e., not the entire file hierarchy).
    #
    # For example, if the Qsys system needs A.v to instantiate module A, then
    # A.v will be listed in the hw.tcl. Every file listed in the hw.tcl also
    # gets copied to system/synthesis/submodules and referenced in system.qip,
    # and system.qip is included in the .qsf, therefore synthesis will be able
    # to find the file A.v. 
    #
    # But if A instantiates module B, B.v does not need to be in the hw.tcl, 
    # since Qsys still is able to find B.v during system generation. So while
    # the Qsys generation will still succeed without B.v listed in the hw.tcl, 
    # B.v will not be copied to submodules/ and will not be included in the .qip,
    # so synthesis will fail while looking for this IP file. This happens in the 
    # virtual fabric flow, where the full hierarchy is not included in the hw.tcl.
    #
    # Since we are using an environment variable in the path, move the
    # assignment to a tcl file and source the file in each qsf (done below).
    my $ip_include = "$work_dir/ip_include.tcl";
    open($fh, '>', $ip_include) or die "Cannot open file '$ip_include' $!";
    print $fh 'set_global_assignment -name SEARCH_PATH "$::env(INTELFPGAOCLSDKROOT)/ip"
';
    close $fh;

    # Set soft region INI and exported qsf setting from previous compile to current one
    # Soft region is a Quartus feature to mitigate swiss cheese problem in incremental compile.
    # When below INIs and soft region qsf settings in ip/board/incremental are applied,
    # Fitter exports ATTRACTION_GROUP_SOFT_REGION qsf settings per partition.
    # This region is approximate area the partition's logic was placed in.
    # If these settings are then set in incremental compile, fitter will try to place the partition in the same area.
    if ( $soft_region_on ) {
      if (open( QUARTUS_INI_FILE, ">>$work_dir/quartus.ini" )) {
        if (! -e "$work_dir/soft_regions.txt") {
          print QUARTUS_INI_FILE <<SOFT_REGION_SETUP_INI;

# Apl blobby
apl_partition_gamma_factor=10
apl_ble_partition_bin_size=4
apl_cbe_partition_bin_size=6
apl_use_partition_based_spreading=on
SOFT_REGION_SETUP_INI
          # Create empty soft_regions.txt file so that
          # ip/board/incremental scripts set soft region qsf settings
          open( SOFT_REGION_FILE, ">$work_dir/soft_regions.txt" ) or die "Cannot open file 'soft_regions.txt' $!";
          print SOFT_REGION_FILE "";
          close (SOFT_REGION_FILE);
        } else {
          # Add exported soft region qsf settings from previous compile to current one
          push @additional_qsf, "$work_dir/soft_regions.txt";
        }

        print QUARTUS_INI_FILE <<SOFT_REGION_INI;

# Apl attraction groups
apl_floating_region_aspect_ratio_factor=100
apl_discrete_dp=off
apl_ble_attract_regions=on
apl_region_attraction_weight=100

# DAP attraction groups
dap_attraction_group_cost_factor=10
dap_attraction_group_use_soft_region=on
dap_attraction_group_v_factor=3.0

# Export soft regions filename
vpr_write_soft_region_filename=soft_regions.txt
SOFT_REGION_INI
        close (QUARTUS_INI_FILE);
      }
    }

    # append users qsf to end to overwrite all other settings
    my $final_append = '';
    if( scalar @additional_qsf ) {
      foreach my $add_q (@additional_qsf){
        open (QSF_FILE, "<$add_q") or die "Couldn't open $add_q for read\n";
        $final_append .= "# Contents automatically added from $add_q\n";
        $final_append .= do { local $/; <QSF_FILE> };
        $final_append .= "\n";
        close (QSF_FILE);
      }
    }

    # Add SEARCH_PATH for ip/$base to the QSF file
    foreach my $qsf_file (acl::File::simple_glob( "$work_dir/*.qsf" )) {
      open (QSF_FILE, ">>$qsf_file") or die "Couldn't open $qsf_file for append!\n";

      # Source a tcl script which points the project to the IP directory
      print QSF_FILE "\nset_global_assignment -name SOURCE_TCL_SCRIPT_FILE ip_include.tcl\n";

      # Case:149478. Disable auto shift register inference for appropriately named nodes
      print "$prog: Adding wild-carded AUTO_SHIFT_REGISTER_RECOGNITION assignment to $qsf_file\n" if $verbose>1;
      print QSF_FILE "\nset_instance_assignment -name AUTO_SHIFT_REGISTER_RECOGNITION OFF -to *_NO_SHIFT_REG*\n";

      # allow for generate loops with bounds over 5000
      print QSF_FILE "\nset_global_assignment -name VERILOG_CONSTANT_LOOP_LIMIT 10000\n";

      # fast-compile options can be appended to qsf files to indicated to quartus that the compile is mainly for
      # functionality and not fmax
      if( $fast_compile_on ) {
        open( QSF_FILE_READ, "<$qsf_file" ) or print "Couldn't open $qsf_file again - overwriting whatever INI_VARS are there\n";
        my $ini_vars = '';
        while( <QSF_FILE_READ> ) {
          if( $_ =~ m/INI_VARS\s+[\"|\'](.*)[\"|\']/ ) {
            $ini_vars = $1;
          }
        }
        close( QSF_FILE_READ );
        print QSF_FILE <<FAST_COMPILE_OPTIONS;
# The following settings were added by --fast-compile
# umbrella fast-compile setting
set_global_assignment -name OPTIMIZATION_TECHNIQUE Balanced
set_global_assignment -name OPTIMIZATION_MODE "Aggressive Compile Time"
FAST_COMPILE_OPTIONS
        my %new_ini_vars = (
        );
        if( $ini_vars ) {
          $ini_vars .= ";";
        }
        keys %new_ini_vars;
        while( my($k, $v) = each %new_ini_vars) {
          $ini_vars .= "$k=$v;";
        }
        if($ini_vars ne '') {
          print QSF_FILE "\nset_global_assignment -name INI_VARS \"$ini_vars\"\n";
        }
      }

      if( scalar @additional_qsf ) {
        print QSF_FILE "\n$final_append\n";
      }

      close (QSF_FILE);
    }
  }

  # Set up for incremental change detection
  my $devicemodel = uc acl::Env::aocl_boardspec( "$board_spec_xml", "devicemodel");
  ($devicemodel) = $devicemodel =~ /(.*)_.*/;
  my $devicefamily = device_get_family_no_normalization($devicemodel);
  my $run_change_detection = $incremental && $input_dir ne "" &&
                            !acl::Incremental::requires_full_recompile($input_dir, $base, $all_aoc_args, acl::Env::board_name(), $board_variant,
                                                                      $devicemodel, $devicefamily, $QUARTUS_VERSION, $prog,
                                                                      "17.1.0", "590");
  warn $acl::Incremental::warning if (defined $acl::Incremental::warning && !$quiet_mode);
  if ($incremental && $run_change_detection) {
    my ($arbitration_latency, $kernel_side_mem_latency) = acl::Incremental::get_global_mem_parameters("$input_dir/$base.bc.xml");
    $llc_arg_after .= " -overwrite-arbitration-latency=$arbitration_latency -overwrite-side-mem-latency=$kernel_side_mem_latency " if ($arbitration_latency && $kernel_side_mem_latency);
  }

  my $optinfile = "$base.1.bc";
  my $pkg = undef;
  my $src_pkg = undef;

  # Copy the CL file to subdir so that archived with the project
  # Useful when creating many design variants
  # But make sure it doesn't end with .cl
  acl::File::copy( $absolute_srcfile, $work_dir."/".acl::File::mybasename($absolute_srcfile).".orig" )
   or mydie("Can't copy cl file to destination directory: $acl::File::error");

  # OK, no turning back remove the result file, so no one thinks we succedded
  unlink "$objfile";
  unlink $src_pkg_file_final;

  if ( $soft_ip_c_flow ) {
      $clang_arg_after = "-x soft-ip-c -soft-ip-c-func-name=$soft_ip_c_name";
  } elsif ($accel_gen_flow ) {
      $clang_arg_after = "-x cl -soft-ip-c-func-name=$accel_name";
  }

  my $is_msvc_2015 = 0;
  # Late environment check IFF we are using the emulator
  if (($emulator_arch eq 'windows64') && ($emulator_flow == 1) ) {
    my $msvc_out = `LINK 2>&1`;
    chomp $msvc_out; 

    if ($msvc_out !~ /Microsoft \(R\) Incremental Linker Version/ ) {
      mydie("$prog: Can't find VisualStudio linker LINK.EXE.\nEither use Visual Studio x64 Command Prompt or run %INTELFPGAOCLSDKROOT%\\init_opencl.bat to setup your environment.\n");
    }
    my ($linker_version) = $msvc_out =~ /(\d+)/;
    if ($linker_version >= 14 ){
      #FB:441273 Since VisualStudio 2015, the way printf is dealt with has changed.
      $is_msvc_2015 = 1;
    }
  }

  if ( $run_clang ) {
    my $clangout = "$base.pre.bc";
    my @cmd_list = ();

    # Create package file in source directory, and save compile options.
    $pkg = create acl::Pkg($pkg_file);

    # Figure out the compiler triple for the current flow.
    my $fpga_triple = 'fpga64';
    my $emulator_triple = ($emulator_arch eq 'windows64') ? 'x86_64-pc-win32' : 'x86_64-unknown-linux-gnu';
    my $cur_flow_triple = $emulator_flow ? $emulator_triple : $fpga_triple;
    
    my @triple_list;
    
    # Triple list to compute.
    if ($created_shared_aoco) {
      @triple_list = ($fpga_triple, 'x86_64-pc-win32', 'x86_64-unknown-linux-gnu');
    } else {
      @triple_list = ($cur_flow_triple);
    }
    
    my $dep_file = "$work_dir/$base.d";
    if ( not $c_acceleration ) {
      print "$prog: Running OpenCL parser....\n" if (!$quiet_mode); 
      chdir $force_initial_dir or mydie("Can't change into dir $force_initial_dir: $!\n");

      # Emulated flows to cover
      my @emu_list = $created_shared_aoco ? (0, 1) : $emulator_flow;

      # These two nested loops should produce either one clang call for regular compiles
      # Or three clang calls for three triples if -shared was specified: 
      #     (non-emulated, fpga), (emulated, linux), (emulated, windows)
      foreach my $emu_flow (@emu_list) {        
        foreach my $cur_triple (@triple_list) {
        
          # Skip {emulated_flow, triple} combinations that don't make sense
          if ($emu_flow and ($cur_triple =~ /fpga/)) { next; }
          if (not $emu_flow and ($cur_triple !~ /fpga/)) { next; }
          
          my $cur_clangout;
          if ($cur_triple eq $cur_flow_triple) {
            $cur_clangout = "$work_dir/$base.pre.bc";
          } else {
            $cur_clangout = "$work_dir/$base.pre." . $cur_triple . ".bc";
          }

          my @debug_options = ( $debug ? qw(-mllvm -debug) : ());
          my @llvm_library_option = ( map { (qw(-libfile), $_) } @resolved_lib_files );
          my @clang_std_opts = ( $emu_flow ? qw(-cc1 -target-abi opencl -emit-llvm-bc -mllvm -gen-efi-tb -Wuninitialized) : qw( -cc1 -O3 -emit-llvm-bc -Wuninitialized));
          my @board_options = map { ('-mllvm', $_) } split( /\s+/, $llvm_board_option );
          my @board_def = (
              "-DACL_BOARD_$board_variant=1", # Keep this around for backward compatibility
              "-DAOCL_BOARD_$board_variant=1",
              );
          my @clang_arg_after_array = split(/\s+/m,$clang_arg_after);
          my @clang_dependency_args = ( ($cur_triple eq $cur_flow_triple) ? ("-MT", "$base.bc", "-sys-header-deps", "-dependency-file", $dep_file) : ());
          
          @cmd_list = (
              $clang_exe, 
              @clang_std_opts,
              ('-triple',$cur_triple),
              @board_options,
              @board_def,
              @debug_options, 
              $absolute_srcfile,
              @clang_arg_after_array,
              @llvm_library_option,
              '-o',
              $cur_clangout,
              @clang_dependency_args,
              @user_clang_args,
              );
          $return_status = mysystem_full(
              {'stdout' => "$work_dir/clang.log",
               'stderr' => "$work_dir/clang.err",
               'time' => 1, 
               'time-label' => 'clang'},
              @cmd_list);
              
          # Only save warnings and errors corresponding to current flow triple.
          # Otherwise, will get all warnings in triplicate.
          if ($cur_triple eq $cur_flow_triple) {
            move_to_log("!========== [clang] parse ==========", "$work_dir/clang.log", "$work_dir/$fulllog"); 
            append_to_log("$work_dir/clang.err", "$work_dir/$fulllog");
            move_to_err("$work_dir/clang.err");
          }
          $return_status == 0 or mydie("OpenCL parser FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
          
          # Save clang output to .aoco file. This will be used for creating
          # a library out of this file.
          # ".acl.clang_ir" section prefix name is also hard-coded into lib/libedit/inc/libedit.h!
          $pkg->set_file(".acl.clang_ir.$cur_triple", $cur_clangout)
               or mydie("Can't save compiler object file $cur_clangout into package file: $acl::Pkg::error\n");
        }
      }
    }

    if ( $parse_only ) { 
      unlink $pkg_file;
      return;
    }

    if ( defined $program_hash ){ 
      save_pkg_section($pkg,'.acl.hash',$program_hash);
    }
    if ($emulator_flow) {
      save_pkg_section($pkg,'.acl.board',$emulatorDevice);
    } elsif ($new_sim_mode) {
      save_pkg_section($pkg,'.acl.board',"SimulatorDevice");
      save_pkg_section($pkg,'.acl.simulator_object',"");
    } else {
      save_pkg_section($pkg,'.acl.board',$board_variant);
    }
    save_pkg_section($pkg,'.acl.compileoptions',join(' ',@user_opencl_args));
    # Set version of the compiler, for informational use.
    # It will be set again when we actually produce executable contents.
    save_pkg_section($pkg,'.acl.version',acl::Env::sdk_version());
    
    print "$prog: OpenCL parser completed successfully.\n" if $verbose;
    if ( $disassemble ) { mysystem("llvm-dis \"$work_dir/$clangout\" -o \"$work_dir/$clangout.ll\"" ) == 0 or mydie("Cannot disassemble: \"$work_dir/$clangout\"\n"); }

    $files = `file-list \"$work_dir/$clangout\"`;
    if ( $profile ) {
      $src_pkg = create acl::Pkg($src_pkg_file);
      save_pkg_section($src_pkg,'.acl.version',acl::Env::sdk_version());
      my $index = 0;
      foreach my $file ( split(/\n/, $files) ) {
         # "Unknown" files are included when opaque objects (such as image objects) are in the source code
         if ($file =~ m/\<unknown\>$/ or $file =~ m/$ocl_header_filename$/) {
            next;
         }
        save_pkg_section($src_pkg,'.acl.file.'.$index,$file);
        $src_pkg->add_file('.acl.source.'. $index,$file)
        or mydie("Can't save source into package file: $acl::Pkg::error\n");
        $index = $index + 1;
      }
      save_pkg_section($src_pkg,'.acl.nfiles',$index);

      $src_pkg->add_file('.acl.source',$absolute_srcfile)
      or mydie("Can't save source into package file: $acl::Pkg::error\n");
    }

    my @patterns_to_skip = ("\<unknown\>", $ocl_header_filename);
    $fileJSON = acl::Report::get_source_file_info_for_visualizer($files, \@patterns_to_skip, [$dep_file], $dash_g);

    # For emulator and non-emulator flows, extract clang-ir for library components
    # that were written using OpenCL
    if ($#resolved_lib_files > -1) {
      foreach my $libfile (@resolved_lib_files) {
        if ($verbose >= 2) { print "Executing: $aocl_libedit_exe extract_clang_ir \"$libfile\" $cur_flow_triple $work_dir\n"; }
        my $new_files = `$aocl_libedit_exe extract_clang_ir \"$libfile\" $cur_flow_triple $work_dir`;
        if ($? == 0) {
          if ($verbose >= 2) { print "  Output: $new_files\n"; }
          push @lib_bc_files, split /\n/, $new_files;
        }
      }
    }
    
    # do not enter to the work directory before this point, 
    # $pkg->add_file above may be called for files with relative paths
    chdir $work_dir or mydie("Can't change dir into $work_dir: $!");

    if ($emulator_flow) {
      print "$prog: Compiling for Emulation ....\n" if (!$quiet_mode);
      # Link with standard library.
      my $emulator_lib = acl::File::abs_path( acl::Env::sdk_root()."/share/lib/acl/acl_emulation.bc");
      @cmd_list = (
          $link_exe,
          "$work_dir/$clangout",
          @lib_bc_files,
          $emulator_lib,
          '-o',
          $optinfile );
      $return_status = mysystem_full(
          {'stdout' => "$work_dir/clang-link.log", 
           'stderr' => "$work_dir/clang-link.err",
           'time' => 1, 'time-label' => 'link (early)'},
          @cmd_list);
      move_to_log("!========== [link] early link ==========", "$work_dir/clang-link.log",
      "$work_dir/$fulllog");
      move_to_err("$work_dir/clang-link.err");
      remove_named_files($clangout) unless $save_temps;
      foreach my $lib_bc_file (@lib_bc_files) {
        remove_named_files($lib_bc_file) unless $save_temps;
      }
      $return_status == 0 or mydie("OpenCL parser FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
      my $debug_option = ( $debug ? '-debug' : '');
      my $emulator_efi_option = ( $#resolved_lib_files > -1 ? '-createemulatorefiwrappers' : '');
      my $opt_optimize_level_string = ($emu_optimize_o3) ? "-O3" : "";

      if ( !(($emu_ch_depth_model eq 'default' ) || ($emu_ch_depth_model eq 'strict') || ($emu_ch_depth_model eq 'ignore-depth')) ) {
        mydie("Invalid argument for option --emulator-channel-depth-model, must be one of <default|strict|ignore-depth>. \n");
      }
      $return_status = mysystem_full(
          {'time' => 1, 
           'time-label' => 'opt (opt (emulator tweaks))'},
          "$opt_exe -verify-get-compute-id -translate-library-calls -reverse-library-translation -lowerconv -scalarize -scalarize-dont-touch-mem-ops -insert-ip-library-calls -createemulatorwrapper -emulator-channel-depth-model $emu_ch_depth_model $emulator_efi_option -generateemulatorsysdesc $opt_optimize_level_string $llvm_board_option $llvm_efi_option $llvm_library_option $debug_option $opt_arg_after \"$optinfile\" -o \"$base.bc\" >>$fulllog 2>opt.err" );
      filter_llvm_time_passes("opt.err");
      move_to_err_and_log("========== [aocl-opt] Emulator specific messages ==========", "opt.err", $fulllog);
      $return_status == 0 or mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");

      $pkg->set_file('.acl.llvmir',"$base.bc")
          or mydie("Can't save optimized IR into package file: $acl::Pkg::error\n");

      #Issue an error if autodiscovery string is larger than 4k (only for version < 15.1).
      my $bsp_version = acl::Env::aocl_boardspec( "$board_spec_xml", "version");
      if( (-s "sys_description.txt" > 4096) && ($bsp_version < 15.1) ) {
        mydie("System integrator FAILED.\nThe autodiscovery string cannot be more than 4096 bytes\n");
      }
      $pkg->set_file('.acl.autodiscovery',"sys_description.txt")
          or mydie("Can't save system description into package file: $acl::Pkg::error\n");

      my $arch_options = ();
      if ($emulator_arch eq 'windows64') {
        $arch_options = "-cc1 -triple x86_64-pc-win32 -emit-obj -o libkernel.obj";
      } else {
        $arch_options = "-fPIC -shared -Wl,-soname,libkernel.so -L\"$ENV{\"INTELFPGAOCLSDKROOT\"}/host/linux64/lib/\" -lacl_emulator_kernel_rt -o libkernel.so";
      }
      
      my $clang_optimize_level_string = ($emu_optimize_o3) ? "-O3" : "-O0";
      
      $return_status = mysystem_full(
          {'time' => 1, 
           'time-label' => 'clang (executable emulator image)'},
          "$clang_exe $arch_options $clang_optimize_level_string \"$base.bc\" >>$fulllog 2>opt.err" );
      filter_llvm_time_passes("opt.err");
      move_to_err_and_log("========== [clang compile kernel emulator] Emulator specific messages ==========", "opt.err", $fulllog);
      $return_status == 0 or mydie("Optimizer FAILED.\nRefer to $base/$fulllog for details.\n");

      if ($emulator_arch eq 'windows64') {
        my $legacy_stdio_definitions = $is_msvc_2015 ? 'legacy_stdio_definitions.lib' : '';
        $return_status = mysystem_full(
            {'time' => 1, 
             'time-label' => 'clang (executable emulator image)'},
            "link /DLL /EXPORT:__kernel_desc,DATA /EXPORT:__channels_desc,DATA /libpath:$ENV{\"INTELFPGAOCLSDKROOT\"}\\host\\windows64\\lib acl_emulator_kernel_rt.lib msvcrt.lib $legacy_stdio_definitions libkernel.obj>>$fulllog 2>opt.err" );
        filter_llvm_time_passes("opt.err");
        move_to_err_and_log("========== [Create kernel loadbable module] Emulator specific messages ==========", "opt.err", $fulllog);
        $return_status == 0 or mydie("Linker FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
        $pkg->set_file('.acl.emulator_object.windows',"libkernel.dll")
            or mydie("Can't save emulated kernel into package file: $acl::Pkg::error\n");
      } else {     
        $pkg->set_file('.acl.emulator_object.linux',"libkernel.so")
          or mydie("Can't save emulated kernel into package file: $acl::Pkg::error\n");
      }

      if(-f "kernel_arg_info.xml") {
        $pkg->set_file('.acl.kernel_arg_info.xml',"kernel_arg_info.xml");
        unlink 'kernel_arg_info.xml' unless $save_temps;
      } else {
        print "Cannot find kernel arg info xml.\n" if $verbose;
      }

      my $compilation_env = compilation_env_string($work_dir,$board_variant,$all_aoc_args,$bsp_flow_name);
      save_pkg_section($pkg,'.acl.compilation_env',$compilation_env);

      # Compute runtime.
      my $stage1_end_time = time();
      log_time ("emulator compilation", $stage1_end_time - $stage1_start_time);

      print "$prog: Emulator Compilation completed successfully.\n" if $verbose;
      &$finalize();
      return;
    } 

    # Link with standard library.
    my $early_bc = acl::File::abs_path( acl::Env::sdk_root()."/share/lib/acl/acl_early.bc");
    @cmd_list = (
        $link_exe,
        "$work_dir/$clangout",
        @lib_bc_files,
        $early_bc,
        '-o',
        $optinfile );
    $return_status = mysystem_full(
        {'stdout' => "$work_dir/clang-link.log", 
         'stderr' => "$work_dir/clang-link.err",
         'time' => 1, 
         'time-label' => 'link (early)'},
        @cmd_list);
    move_to_log("!========== [link] early link ==========", "$work_dir/clang-link.log",
        "$work_dir/$fulllog");
    move_to_err("$work_dir/clang-link.err");
    remove_named_files($clangout) unless $save_temps;
    foreach my $lib_bc_file (@lib_bc_files) {
      remove_named_files($lib_bc_file) unless $save_temps;
    }
    $return_status == 0 or mydie("OpenCL linker FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
  }

  chdir $work_dir or mydie("Can't change dir into $work_dir: $!");

  my $disabled_lmem_replication = 0;
  my $restart_acl = 1;  # Enable first iteration
  my $opt_passes = $dft_opt_passes;
  if ( $soft_ip_c_flow ) {
      $opt_passes = $soft_ip_opt_passes;
  }

  if ( $run_opt_vfabric ) {
    print "$prog: Compiling with Rapid Prototyping flow....\n" if $verbose;
    $restart_acl = 0;
    my $debug_option = ( $debug ? '-debug' : '');
    my $profile_option = ( $profile ? "-profile $profile" : '');

    # run opt
    $return_status = mysystem_full(
        {'time' => 1, 'time-label' => 'opt ', 'stdout' => 'opt.log', 'stderr' => 'opt.err'},
        "$opt_exe --acle ljg7wvyc1geoldvzy1bknywbngf1qb17frkm0t0zbrebqj07ekh3nrwxc2f1qovp3xd38uui32qclkjpatdzqkpbcrk33czpyxjb0tjo1gu7qgwpk3h72tfxmrkmn3ppl2vs0rdovx713svzkhhfnedx1rzbtijzgggh0qyi720qqkwojhdonj0xcracmczpq2z3uhb7yv1c2y77ekh3njvc7ra1q8dolxfhwtfmireznrpokcdknw0318a7qxvp1rkb0uui3gleqgfpttd7mtvcura1q3ypdgg38uui32wmljwpekh3lqjxcrkbtijz32h37ujibglkmsjzy1bknyvbzga3loype2s7wywo880qqkvot3jfnupblgd3low7ljg7wu0o7x713svze3j1qq8v18a7mvjolxbbyw0oprl7lgpoekh3nt0vwgd7q3w7ljg7wrporgukqgpoy1bkny8xxxkcnvvpagkuwwdo880qqkvok3h7qq8x2gh7qxvzt8vs0ryoeglzmr8pshhmlhwblxk33czpy2km7yvzrrluqswokthkluu3xxf7nvyzs2kmegdoyxl13svz3tdmluu3xxfbmbdos2sbyw0o3ru1mju7atj3meyxwrauqxyiljg7wepi2rebmawp3cvorlvcigjkq187frkceq8z72e3qddpqcvorlvc7rjcl8ypu2dc7uvzrrlcljjzucfqnldx0jpsmvjzdgfm7uji1xy1mgy7atj7qjjxwgfzmb0ogrgswtfmirezldyp8chqlr8vm2dzqb17frkuww0zwreeqapzkhholuu3xxfcnbypsrk1weji7xlkqa07ekh3nj8xbrkhmzpzxrko0yvm7jlzmuyzutd3mlvczgfcncw7ljg7wewioxu13svz2thzmuwb1rzbtijzs2h70evm7jlzmajpscdorlvcu2a7n2ypmrkt0uui3xyhmuyz3cghlqwc18acq1e7ljg7wewioxu13svz7hh3mg8xyxftqb17frkuww0zwreeqapzkhholuu3xxfuqi0z72km7gvm7jlzmajpscdorlvczrdumi8pt8vs0rjiorlclgfptckolqycygsfqiw7ljg70yyzix713svzf3ksny0bfxa3l3w7ljg70g0o3xuctgfpt3gknjwbmxakqvypf2j38uui3gq1la0oekh3lh0xlgd1qcypfrj38uui3reemupoechmlhyc8gpsmvwo1rg37two1xykqsdpy1bknywcqgd33czpy2kc0rdo880qqkvok3h7qq8x2gh7qxvzt8vs0rpiiru3lkjpfhjqllyc0jpsmvjomgfuwhdmire3qg8zw3bkny0blxacni0oxxfb0gvm7jlzqhwpshjmlqwcmgd33czpyrkfww0zw2l1mujzecvorlvcngfml8yplgf38uui3reemsdoehdzmtfxmgsfq80zljg70qwiqgu13svz0thorlvcz2acl8ypfrfu0r0z880qqkwpsth7mtfxmxkumowos2ho0svm7jlzmavz3tdmluu3xxfhmivp32vs0rdziguemawpy1bknyvbzga3loype2s7wywo880qqkvottj7quu3xxfzq2ppt8vs0rdi72lzmy8iscdzquu3xxfuqijomrkf0e8obgl1mju7atjunhyxwgpsmv0ohgfb0tjobgl7mju7atj3nlpblgdhmb0olxjbyw0oyguemy8zq3jzmejxxrzbtijzqrfbwtfmirebmgvzecvorlvcqgskq10pggju7ryomx713svzkhh3qhvccgammzpplxbbyw0otxyold0oekh3ltyc7rdbtijz3gffwkwiw2tclgvoy1bknyjcvxammb0pqrkbwtfmirezqsdp3cfsntpb3gd33czpygk1wg8zb2wonju7atjmlqjb7gh7nczpy2hswepii2wctgfpthhhljyxlgdclb17frkc0yyze2wctgfpt3j3lqy3xxfhmiyzq2vs0r0zwrlolgy7atjqllwblgssm8ypyrfbyw0o1xw3mju7atjfnljb12k7mipp7xbbyw0o0re1mju7atjmlqjb7gh7nczpygfb0ewil2w13svzf3ksntfxmgssq3doggg77q0otx713svz23ksnldb1gpsmvvpdgkbyw0o1rezqgvo33k3quu3xxfcmv8zt8vs0r0z32etqjpo23k7qq0318a7qcjzlxbbyw0oeru1qgfptcd1medbl8kbmx87frkceq8z7ruhqswpwcvorlvcw2kuq2dm12jz0uui3xyhmuyz3cghlqwc18acm8fmt8vs0rvzr2qmnuzoetk72tfxm2kbmovp72jbyw0obglkmr8puchqld8cygsfqi87frk7ekwir2wznju7atj1mtyxc2jbmczpy2ds0jpoixy1mgy7atj3nuwxvxk33czpyxfm7wdioxy1mypokhf72tfxmgfcmv8zt8vs0rjiorlclgfpttdqnq0bvgsom7w7ljg7whvib20qqkvzs3jfntvbmgssmxw7ljg70gpizxutqddzbtjbnr0318a7mzpp8xd70wdi22qqqg07ekh3ltvc1rzbtijze2ht7kvz7jlzmk8p0tjmnjwbqrzbtijzs2g77uui32l1mujze3bkny8cvra33czpyxgk0udi7jlzqu0od3gzqhyclrzbtijz72jm7qyokx713svzath1mqwxqrzbtijzrxdcegpi22y3lg0o2th7mujc7rjumippt8vs0rwolglctgfptck3nt0318a7m8ypaxfh0qyokremqh07ekh3lqvby2kbnv0oggjuetfmirekmsvo0tjhnqpcz2abmczpyggf0uui3gyctgfpttd3nuwx72kuq08zljg7weporrw1qgfpt3jcnrpb1xd1q38z8xbbyw0otrebma8z2hdolkwx0jpsmv0zy2j38uui3gwkmwyo83bknypczrj7mbjomrf38uui3xleqtyz2tdcmewbmrs33czpyrf70tji1gukmeyzekh3ltjxxrjbtijzmrgb7rvi7jl3mrpo73k72tfxmxk7mb0prgfuwado880qqkwzt3k72tfxmgfcmv8zt8vs0rwolglctgfptck3nt0318a7mzpp8xd70wdi22qqqg07ekh3lkpbcxdmnb8pljg70yjiogebmay7atjsntyx0jpsmvwo1rgzwgpoz20qqkjzdth1nuwx18a7mo8za2vs0rdzt2e7qg07ekh3njvxzrkbtijz8xjuwjdmireznuyzf3bknyjxwrj33czpyxdm7qyzb2etqgfpt3hmlh0x0jpsmvypfxjbws0zq2ecny8patk72tfxmrjmnbpp8gjfwgdi7jlzmypokhhzqr0318a7qovpdxfbyw0ot2qumywpkhkqquu3xxfhmvjo82k38uui32l1majpscd72tfxm2jbq8ype2s38uui3xleqs0oekh3nj8xbrkhmzpzxxbbyw0oprezlu8zy1bknypcn2dmncyoljg70tyiirl3ljwoecvorlvcn2k1qijzh2vs0r0ooglmlgpo33ghllp10jpsmv0zy2j38uui32qqquwotthsly8xxgd33czpygdb0rjzogukmeyzekh3nwycl2abqow7ljg7wjdor2qmqw07ekh3nrdbxrzbtijzggg7ek0oo2loqddpecvorlvc8xfbqb17frko7u8zbgwknju7atj1mtyxc2jbmczpyxjb0tjo7jlzquwoshdonj0318a7qcjzlxbbyw0ol2wolddzbcvorlvcbgdmnx8zljg7wh8z7xwkqk8z03kzntfxmxkcnidolrf38uui3xwzqg07ekh3nedxqrj7mi8pu2hs0uvm7jlzqjwzt3k72tfxmraumv8pt8vs0rjiorlclgfpttjhnqpcz2abqb17frkh0q0ozx713svzn3k1medcfrzbtijzsrgfwhdmire3nu8p8tjhnhdxygpsmvyzfggfwkpow2wctgfpttj1lk0318a7q28z12ho0svm7jlzqddp3cf3nlyxngssmcw7ljg70yyzix713svz33gslkwxz2dunvpzwxbbyw0oz2wolhyz23kzmhpbxrzbtijz82hkwhjibgwklkdzqcvorlvcvxazncdo8rduwk0ovx713svzqhfkluu3xxfcl8yp72h1wedmireuqjwojcvorlvc8xfbqb17frk77ujz1xlkqhdpf3kklhvb0jpsmvpolgfuwypp880qqkpoeckomyyc18a7q88z8rgbeg0o7ructgfptck3nt0318a7q28z12ho0svm7jlzqjwzg3f3qhy3xxf7nzdilrf38uui3rukqa0od3gbnfvc2xd33czpyxgf0jdorru7ldwotcg72tfxm2f1q8dog2jm7gjzkxl1mju7atjznyyc0jpsmvypfrfc7rwizgekmsyzy1bknywcmgd33czpy2gb0edmireoqjdph3bkny0bc2kcnczpy2k77gpimgluqgdp0cvorlvcvxa7mb0pljg70edoz20qqkwpkhkolh8xbgd7nczpyxjfwwjz7jlzqkjpfcdoqhyc0jpsmv0p0rjh0qyit2wonr07ekh3nuwxtgfun887frkm7ujzeguqqgfptcgcmgjczrd33czpygfbwkviqry7qdwzy1bknydb2rk1mvjpgxj7etfmire7lddpy1bknyjbc2kemz0ol2gbyw0obgl3nu8patdqnyvb18a7qovp02jm7u8z880qqkdz7tdontfxmrjmnzvzdggf0edowgukqky7atjbnhdxmrjumipp8xbbyw0o0rl1nkwpe3bkny0buga3nczpygj37uui32yqqdwoy1bkny8xxxkcnvvpagkuwwdo880qqkwzt3k72tfxm2d3nv87frkc0u0oo2lclsvokcfqnldx0jpsmvypfrfc7rwizgekmsyzy1bknywcmgd33czpygj37rdmirezqsdpn3k1mj8xc2abtijz12jk0wyz1xlctgfpt3gknjwbmxakqvypf2j38uui3xwzqg07ekh3nrdbxrzbtijzaxfcwtfmireolgwz7tjontfxmrdbq18zfxjbww0o720qqkwzktdzmudxmgd33czpy2kmegpok20qqk0o23gbquu3xxf1qippdxd1wkdo7jlzqayzfckolk0318a7q10pdrg37uui3xukmyyzd3gknedx3gpsmvpoe2kmwgpi3x713svz8hdontfxmrafmiwoljg7whpiy2wtqddpkhhcluu3xxfmnc8pdgdb0uui3xw1nywpktjmlhyc18a7qcdzwxbbyw0omgyqmju7atjqllvbyxffmodzgggbwtfmirebmgvzecvorlvcqxfuq2w7ljg7wewioxu13svz83g7mtwxz2auqivzt8vs0rpiiru3lkjpfhjqllyc0jpsmv0zy2j38uui3gu1qajpn3korlvc8gj3loypy2kc7udmire3mkjzy1bknyvbzga3loype2s7wywo880qqkwpstfoljvbtgscnvwpt8vs0rjooxy13svzthkcntfxmrafmiwoljg7whpiy2wtqddpkhhcluu3xxf1qcdpnrfc7uui3rukmeyz3cvorlvcrgdmnzpzxxbbyw0ol2wolddzbcvorlvcmxasq28z1xdbyw0o7xt3lgfptcfhntfxmxkbqo8zyxd38uui3gy1qkwoshdqldyc18a7mzpp8xd7etfmire3qkyzy1bknyjcr2a33czpyxj70uvm7jlzqddp3cf3nlyxngssmcw7ljg7wu0o7x713svz23ksnuwb12kumb0pggsb0uui3gwemuy7atjbqr8cnrzbtijz12jk0tjz7gukqjwpkhaoluu3xxfcmv8zt8vs0rjzr2qmld8zd3bkny8xxxkcn887frko0w8z7jlzmtdzuhj72tfxmrjmnzpog2kh0uui32qqquwo23f3lh8xc2abtijz12j3eepi32e3ldjpacvorlvc1rh3nijol2vs0rjibgy1qgfpthfmlqyb1xk33czpyxj70uvmijn $llvm_board_option $debug_option $opt_arg_after \"$optinfile\" -o \"$base.bc\"" );
    filter_llvm_time_passes('opt.err');
    move_to_log("!========== [opt] ==========", 'opt.log', 'opt.err', $fulllog);
    move_to_err('opt.err'); # Warnings/errors
    if ($return_status != 0) {
      mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
    }

    # Finish up opt-like steps.
    if ( $run_opt || $run_opt_vfabric ) {
      if ( $disassemble || $soft_ip_c_flow ) { mysystem("llvm-dis \"$base.bc\" -o \"$base.ll\"" ) == 0 or mydie("Cannot disassemble: \"$base.bc\"\n"); }
      if ( $pkg_save_extra ) {
        $pkg->set_file('.acl.llvmir',"$base.bc")
        or mydie("Can't save optimized IR into package file: $acl::Pkg::error\n");
      }
      if ( $opt_only ) { return; }
    }
    if ( $run_vfabric_cfg_gen ) {
      my $debug_option = ( $debug ? '-debug' : '');
      my $vfab_lib_path = (($custom_vfab_lib_path) ? $custom_vfab_lib_path : 
              $acl_board_hw_path."_vfabric");

      print "vfab_lib_path = $vfab_lib_path\n" if $verbose>1;

      # Check that this a valid board directory by checking for at least 1 
      # virtual fabric variant in the board directory.
      if (!-f $vfab_lib_path."/var1.txt" && !$generate_vfabric) {
        mydie("Cannot find Rapid Prototyping Library for board '$board_variant' in Rapid Prototyping flow. Run with '--create-template' flag to build new Rapid Protyping templates for this board.");
      }

      # check that this library matches the board_variant we are asked to compile to
      my $vfab_sys_file = "$vfab_lib_path/sys_description.txt";

      if (-f $vfab_sys_file) {
        open SYS_DESCR_FILE, "<$vfab_sys_file" or mydie("Invalid Rapid Prototyping Library Directory");
        my $vfab_sys_str = <SYS_DESCR_FILE>;
        chomp($vfab_sys_str);
        close SYS_DESCR_FILE;
        my @sys_split = split(' ', $vfab_sys_str);
        if ($sys_split[1] ne $board_variant) {
          mydie("Rapid Prototyping Library located in $vfab_lib_path is generated for board '$sys_split[1]' and cannot be used for board '$board_variant'.\n Please specify a different Library path.");
        }
      }
      remove_named_files("vfabv.txt");

      my $vfab_args = "-vfabric-library $vfab_lib_path";
      $vfab_args .= ($generate_vfabric ? " -generate-fabric-from-reqs " : "");
      $vfab_args .= ($reuse_vfabrics ? " -reuse-existing-fabrics " : "");

      if ($vfabric_seed) {
         $vfab_args .= " -vfabric-seed $vfabric_seed ";
      }
      $return_status = mysystem_full(
          {'time' => 1, 'time-label' => 'llc', 'stdout' => 'llc.log', 'stderr' => 'llc.err'},
          "$llc_exe  -VFabric -march=virtualfabric $llvm_board_option $debug_option $profile_option $vfab_args $llc_arg_after \"$base.bc\" -o \"$base.v\"" );
      filter_llvm_time_passes('llc.err');
      move_to_log("!========== [llc] vfabric ==========", 'llc.log', 'llc.err', $fulllog);
      move_to_err('llc.err');
      if ($return_status != 0) {
        if (!$generate_vfabric) {
          mydie("No suitable Rapid Prototyping templates found.\nPlease run with '--create-template' flag to build new Rapid Prototyping templates.");
        } else {
          mydie("Rapid Prototyping template generation failed.");
        }
      }

      if ( $generate_vfabric ) {
        # add the complete vfabric configuration file to the package
        $pkg->set_file('.acl.vfabric', $work_dir."/vfabric_settings.bin")
           or mydie("Can't save Rapid Prototyping configuration file into package file: $acl::Pkg::error\n");
        if ($reuse_vfabrics && open VFAB_VAR_FILE, "<vfabv.txt") {
           my $var_id = <VFAB_VAR_FILE>;
           chomp($var_id);
           close VFAB_VAR_FILE;
           acl::File::copy( $vfab_lib_path."/var".$var_id.".txt", "vfab_var1.txt" )
              or mydie("Cannot find reused template: $acl::File::error");
        }
      } else {
        # Virtual Fabric flow is done at this point (don't need to generate design)
        # But now we can go copy over the selected sof 
        open VFAB_VAR_FILE, "<vfabv.txt" or mydie("No suitable Rapid Prototyping templates found.\nPlease run with '--create-template' flag to build new Rapid Prototyping templates.");
        my $var_id = <VFAB_VAR_FILE>;
        chomp($var_id);
        close VFAB_VAR_FILE;
        print "Selected Template $var_id\n" if $verbose;

        save_vfabric_files_to_pkg($pkg, $var_id, $vfab_lib_path, $work_dir, $board_variant);

        # Save the profile XML file in the aocx
        if ( $profile ) {
          save_profiling_xml($pkg,$base);
        }

        my $board_xml = get_acl_board_hw_path($board_variant)."/board_spec.xml";
        if (-f $board_xml) {
           $pkg->set_file('.acl.board_spec.xml',"$board_xml")
                or mydie("Can't save boardspec.xml into package file: $acl::Pkg::error\n");
        }else {
           print "Cannot find board spec xml\n"
        }

        my $compilation_env = compilation_env_string($work_dir,$board_variant,$all_aoc_args,$bsp_flow_name);
        save_pkg_section($pkg,'.acl.compilation_env',$compilation_env);

        # Compute runtime.
        my $stage1_end_time = time();
        log_time ("virtual fabric compilation", $stage1_end_time - $stage1_start_time);

        print "$prog: Rapid Prototyping compilation completed successfully.\n" if $verbose;
        &$finalize(); 
        return;
      }
    }
  }

  my $iterationlog="iteration.tmp";
  my $iterationerr="$iterationlog.err";
  unlink $iterationlog; # Make sure we don't inherit from previous runs
  if ($griffin_flow) {
    # For the Griffin flow, we need to enable a few passes and change a few flags.
    $opt_arg_after .= " --grif --soft-elementary-math=false --fas=false --wiicm-disable=true";
  }

  while ($restart_acl) { # Might have to restart with lmem replication disabled
    unlink $iterationlog unless $save_temps;
    unlink $iterationerr; # Always remove this guy or we will get duplicates to the the screen;
    $restart_acl = 0; # Don't restart compiling unless lmem replication decides otherwise

    if ( $run_opt ) {
      print "$prog: Optimizing and doing static analysis of code...\n" if (!$quiet_mode);
      my $debug_option = ( $debug ? '-debug' : '');
      my $profile_option = ( $profile ? "-profile $profile" : '');

      # Opt run
      $return_status = mysystem_full(
          {'time' => 1, 'time-label' => 'opt', 'stdout' => 'opt.log', 'stderr' => 'opt.err'},
          "$opt_exe $opt_passes $llvm_board_option $llvm_efi_option $llvm_library_option $debug_option $profile_option $opt_arg_after \"$optinfile\" -o \"$base.kwgid.bc\"");
      filter_llvm_time_passes('opt.err');
      append_to_log('opt.err', $iterationerr);
      move_to_log("!========== [opt] optimize ==========", 
          'opt.log', 'opt.err', $iterationlog);
      if ($return_status != 0) {
        move_to_log("", $iterationlog, $fulllog);
        move_to_err($iterationerr);
        mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
      }

      if ( $use_ip_library && $use_ip_library_override ) {
        print "$prog: Linking with IP library ...\n" if $verbose;
        # Lower instructions to IP library function calls
        $return_status = mysystem_full(
            {'time' => 1, 'time-label' => 'opt (ip library prep)', 'stdout' => 'opt.log', 'stderr' => 'opt.err'},
            "$opt_exe -insert-ip-library-calls $opt_arg_after \"$base.kwgid.bc\" -o \"$base.lowered.bc\"");
        filter_llvm_time_passes('opt.err');
        append_to_log('opt.err', $iterationerr);
        move_to_log("!========== [opt] ip library prep ==========", 'opt.log', 'opt.err', $iterationlog);
        if ($return_status != 0) {
          move_to_log("", $iterationlog, $fulllog);
          move_to_err($iterationerr);
          mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
        }
        remove_named_files("$base.kwgid.bc") unless $save_temps;

        # Link with the soft IP library 
        my $late_bc = acl::File::abs_path( acl::Env::sdk_root()."/share/lib/acl/acl_late.bc");
        $return_status = mysystem_full(
            {'time' => 1, 'time-label' => 'link (ip library)', 'stdout' => 'opt.log', 'stderr' => 'opt.err'},
            "$link_exe \"$base.lowered.bc\" $late_bc -o \"$base.linked.bc\"" );
        filter_llvm_time_passes('opt.err');
        append_to_log('opt.err', $iterationerr);
        move_to_log("!========== [link] ip library link ==========", 'opt.log', 'opt.err', $iterationlog);
        if ($return_status != 0) {
          move_to_log("", $iterationlog, $fulllog);
          move_to_err($iterationerr); 
          mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
        }
        remove_named_files("$base.lowered.bc") unless $save_temps;

        # Inline IP calls, simplify and clean up
        $return_status = mysystem_full(
            {'time' => 1, 'time-label' => 'opt (ip library optimize)', 'stdout' => 'opt.log', 'stderr' => 'opt.err'},
            "$opt_exe $llvm_board_option $llvm_efi_option $llvm_library_option $debug_option -always-inline -add-inline-tag -instcombine -adjust-sizes -dce -stripnk -rename-basic-blocks $opt_arg_after \"$base.linked.bc\" -o \"$base.bc\"");
        filter_llvm_time_passes('opt.err');
        append_to_log('opt.err', $iterationerr);
        move_to_log("!========== [opt] ip library optimize ==========", 'opt.log', 'opt.err', $iterationlog);
        if ($return_status != 0) {
          move_to_log("", $iterationlog, $fulllog);
          move_to_err($iterationerr); 
          mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
        }
        remove_named_files("$base.linked.bc") unless $save_temps;
      } else {
        # In normal flow, lower the acl kernel workgroup id last
        $return_status = mysystem_full(
            {'time' => 1, 'time-label' => 'opt (post-process)', 'stdout' => 'opt.log', 'stderr' => 'opt.err'},
            "$opt_exe $llvm_board_option $llvm_efi_option $llvm_library_option $debug_option \"$base.kwgid.bc\" -o \"$base.bc\"");
        filter_llvm_time_passes('opt.err');
        append_to_log('opt.err', $iterationerr);
        move_to_log("!========== [opt] post-process ==========", 'opt.log', 'opt.err', $iterationlog);
        if ($return_status != 0) {
          move_to_log("", $iterationlog, $fulllog);
          move_to_err($iterationerr); 
          mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
        }
        remove_named_files("$base.kwgid.bc") unless $save_temps;
      }
    }

    # Finish up opt-like steps.
    if ( $run_opt ) {
      if ( $disassemble || $soft_ip_c_flow ) { mysystem("llvm-dis \"$base.bc\" -o \"$base.ll\"" ) == 0 or mydie("Cannot disassemble: \"$base.bc\" \n"); }
      if ( $pkg_save_extra ) {
        $pkg->set_file('.acl.llvmir',"$base.bc")
           or mydie("Can't save optimized IR into package file: $acl::Pkg::error\n");
      }
      if ( $opt_only ) { return; }
    }

    if ( $run_verilog_gen ) {
      my $debug_option = ( $debug ? '-debug' : '');
      my $profile_option = ( $profile ? "-profile $profile" : '');
      my $llc_option_macro = $griffin_flow ? ' -march=griffin ' : ' -march=fpga -mattr=option3wrapper -fpga-const-cache=1';

      # Run LLC
      $return_status = mysystem_full(
          {'time' => 1, 'time-label' => 'llc', 'stdout' => 'llc.log', 'stderr' => 'llc.err'},
          "$llc_exe $llc_option_macro $llvm_board_option $llvm_efi_option $llvm_library_option $llvm_profilerconf_option $debug_option $profile_option $llc_arg_after \"$base.bc\" -o \"$base.v\"");
      filter_llvm_time_passes('llc.err');
      append_to_log('llc.err', $iterationerr);

      move_to_log("!========== [llc] ==========", 'llc.log', 'llc.err', $iterationlog);
      if ($return_status != 0) {
        move_to_log("", $iterationlog, $fulllog);
        move_to_err($iterationerr);
        open LOG, "<$fulllog";
        while (my $line = <LOG>) {
          print $win_longpath_suggest if (win_longpath_error_llc($line) and isWindowsOS());
        }
        mydie("Verilog generator FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
      }

      # If estimate > $max_mem_percent_with_replication of block ram, rerun opt with lmem replication disabled
     print "Checking if memory usage is larger than $max_mem_percent_with_replication%\n" if $verbose && !$disabled_lmem_replication;
      my $area_rpt_file_path = $work_dir."/area.json";
      my $xml_file_path = $work_dir."/$base.bc.xml";
      my $restart_without_lmem_replication = 0;
      if (-e $area_rpt_file_path) {
        my @area_util = get_area_percent_estimates();
        if ( $area_util[3] > $max_mem_percent_with_replication && !$disabled_lmem_replication ) {
          # Check whether memory replication was activate
          my $repl_factor_active = 0;
          if ( -e $xml_file_path ) {
            open my $xml_handle, '<', $xml_file_path or die $!;
            while ( <$xml_handle> ) {
              my $xml = $_;
              if ( $xml =~ m/.*LOCAL_MEM.*repl_fac="(\d+)".*/ ) {
                if ( $1 > 1 ) {
                  $repl_factor_active = 1;
                }
              }
            }
            close $xml_handle;
          }

          if ( $repl_factor_active ) {
            print "$prog: Restarting compile without lmem replication because of estimated overutilization!\n" if $verbose;
            $restart_without_lmem_replication = 1;
          }
        }
      } else {
        print "$prog: Cannot find area.json. Disabling lmem optimizations to be safe.\n";
        $restart_without_lmem_replication = 1;
      }
      if ( $restart_without_lmem_replication ) {
        $opt_arg_after .= $lmem_disable_replication_flag;
        $llc_arg_after .= $lmem_disable_replication_flag;
        $disabled_lmem_replication = 1;
        redo;  # Restart the compile loop
      }
    }
  } # End of while loop

  my $report_time = time();
  create_reporting_tool($fileJSON, $base, $all_aoc_args, $board_variant, $disabled_lmem_replication, $devicemodel, $devicefamily);
  log_time("Generate static reports", time()-$report_time);

  if (!$vfabric_flow) {
    move_to_log("",$iterationlog,$fulllog);
    move_to_err($iterationerr);
    remove_named_files($optinfile) unless $save_temps;
  }

  #Put after loop so we only store once
  if ( $pkg_save_extra ) {
    $pkg->set_file('.acl.verilog',"$base.v")
      or mydie("Can't save Verilog into package file: $acl::Pkg::error\n");
  }  

  # Move all JSON files to the reports directory.
  # Do not remove Area Report JSON file - this file is removed after we get the
  # information needed to generate the Estimated Resource Usage Summary table.
  my $json_dir = "$work_dir/reports/lib/json";
  my @json_files = ("area_src", "loops", "summary", "lmv", "mav_old", "mav", "info", "warnings");
  foreach (@json_files) {
    my $json_file = $_.".json";
    if ( -e $json_file ) {
      # There is no acl::File::move, so copy and remove instead.
      acl::File::copy($json_file, "$json_dir/$json_file")
        or warn "Can't copy $_.json to $json_dir\n";
      remove_named_files($json_file) unless $save_temps;
    }
  }

  # Save Area Report JSON file
  # This file is removed after we get the information needed to
  # generate the Estimated Resource Usage Summary table.
  if ( -e "area.json" ) {
    acl::File::copy("area.json", "$json_dir/area.json")
      or warn "Can't copy $_.json to $json_dir\n";
  }

  # Save Area Report HTML file
  if ( -e "area.html" ) {
    remove_named_files("area.html") unless $save_temps;
  }
  elsif ( $verbose > 0 ) {
    print "Missing area report information. aocl analyze-area will " .
          "not be able to generate the area report.\n";
  }

  # Save the profile XML file in the aocx
  if ( $profile ) {
    save_profiling_xml($pkg,$base);
  }

  # Move over the Optimization Report to the log file
  if ( -e "opt.rpt" ) {
    append_to_log( "opt.rpt", $fulllog );
    unlink "opt.rpt" unless $save_temps;
  }

  unlink "report.out";
  if (( $estimate_throughput ) && ( !$accel_gen_flow ) && ( !$soft_ip_c_flow )) {
      print "Estimating throughput since \$estimate_throughput=$estimate_throughput\n";
    $return_status = mysystem_full(
        {'time' => 1, 'time-label' => 'opt (throughput)', 'stdout' => 'report.out', 'stderr' => 'report.err'},
        "$opt_exe -print-throughput -throughput-print $llvm_board_option $opt_arg_after \"$base.bc\" -o $base.unused" );
    filter_llvm_time_passes("report.err");
    move_to_err_and_log("Throughput analysis","report.err",$fulllog);
  }
  unlink "$base.unused";

  # Guard probably deprecated, if we get here we should have verilog, was only used by vfabric
  if ( $run_verilog_gen && !$vfabric_flow) {

    # Round these numbers properly instead of just truncating them.
    my @all_util = get_area_percent_estimates();
    remove_named_files("area.json") unless $save_temps;

    open LOG, ">>report.out";
    printf(LOG "\n".
          "!===========================================================================\n".
          "! The report below may be inaccurate. A more comprehensive           \n".
          "! resource usage report can be found at $base/reports/report.html    \n".
          "!===========================================================================\n".
          "\n".
          "+--------------------------------------------------------------------+\n".
          "; Estimated Resource Usage Summary                                   ;\n".
          "+----------------------------------------+---------------------------+\n".
          "; Resource                               + Usage                     ;\n".
          "+----------------------------------------+---------------------------+\n".
          "; Logic utilization                      ; %4d\%                     ;\n".
          "; ALUTs                                  ; %4d\%                     ;\n".
          "; Dedicated logic registers              ; %4d\%                     ;\n".
          "; Memory blocks                          ; %4d\%                     ;\n".
          "; DSP blocks                             ; %4d\%                     ;\n".
          "+----------------------------------------+---------------------------;\n",
          $all_util[0], $all_util[1], $all_util[2], $all_util[3], $all_util[4]);
    close LOG;

    append_to_log ("report.out", $fulllog);
  }
  if ($report) {
    open LOG, "<report.out";
    print STDOUT <LOG>;
    close LOG;
  }
  unlink "report.out" unless $save_temps;

  if ($save_last_bc) {
    $pkg->set_file('.acl.profile_base',"$base.bc")
      or mydie("Can't save profiling base listing into package file: $acl::Pkg::error\n");
  }
  remove_named_files("$base.bc") unless $save_temps or $save_last_bc;

  my $xml_file = "$base.bc.xml";
  my $sysinteg_debug .= ($debug ? "-v" : "" );

  if ($vfabric_flow) {
    $xml_file = "virtual_fabric.bc.xml";
    $sysinteg_arg_after .= ' --vfabric ';
  }

  if ($run_change_detection) {
    $return_status = mysystem_full(
        {'time' => 1, 'time-label' => 'incremental change detection', 'stdout' => 'si.log', 'stderr' => 'si.err'},
        "$detectchanges_exe $input_dir/$xml_file $xml_file" );
    move_to_log("!========== [DetectChanges] ==========", 'si.log', $fulllog);
    move_to_err_and_log("",'si.err', $fulllog);
    $return_status == 0 or mydie("Incremental change detection FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
  }

  my $version = ::acl::Env::aocl_boardspec( ".", "version");
  my $generic_kernel = ::acl::Env::aocl_boardspec( ".", "generic_kernel".$bsp_flow_name);
  my $qsys_file = ::acl::Env::aocl_boardspec( ".", "qsys_file".$bsp_flow_name);
  ( $generic_kernel.$qsys_file !~ /error/ ) or mydie("BSP compile-flow $bsp_flow_name not found\n");

  if ( $generic_kernel or ($version eq "0.9" and -e "base.qsf")) 
  {
    if ($qsys_file eq "none") {
      $return_status = mysystem_full(
          {'time' => 1, 'time-label' => 'system integrator', 'stdout' => 'si.log', 'stderr' => 'si.err'},
          "$sysinteg_exe $sysinteg_debug $sysinteg_arg_after $board_spec_xml \"$xml_file\" none kernel_system.tcl" );
    } else {
      $return_status = mysystem_full(
          {'time' => 1, 'time-label' => 'system integrator', 'stdout' => 'si.log', 'stderr' => 'si.err'},
          "$sysinteg_exe $sysinteg_debug $sysinteg_arg_after $board_spec_xml \"$xml_file\" system.tcl kernel_system.tcl" );
    }
  } else {
    if ($qsys_file eq "none") {
      mydie("A board with 'generic_kernel' set to \"0\" and 'qsys_file' set to \"none\" is an invalid combination in board_spec.xml! Please revise your BSP for errors!\n");  
    }
    $return_status = mysystem_full(
        {'time' => 1, 'time-label' => 'system integrator', 'stdout' => 'si.log', 'stderr' => 'si.err'},
        "$sysinteg_exe $sysinteg_debug $sysinteg_arg_after $board_spec_xml \"$xml_file\" system.tcl" );
  }
  move_to_log("!========== [SystemIntegrator] ==========", 'si.log', $fulllog);
  move_to_err_and_log("",'si.err', $fulllog);
  $return_status == 0 or mydie("System integrator FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");

  #Issue an error if autodiscovery string is larger than 4k (only for version < 15.1).
  my $bsp_version = acl::Env::aocl_boardspec( "$board_spec_xml", "version");
  if( (-s "sys_description.txt" > 4096) && ($bsp_version < 15.1) ) {
    mydie("System integrator FAILED.\nThe autodiscovery string cannot be more than 4096 bytes\n");
  }
  $pkg->set_file('.acl.autodiscovery',"sys_description.txt")
    or mydie("Can't save system description into package file: $acl::Pkg::error\n");

  if(-f "autodiscovery.xml") {
    $pkg->set_file('.acl.autodiscovery.xml',"autodiscovery.xml")
      or mydie("Can't save system description xml into package file: $acl::Pkg::error\n");    
  } else {
     print "Cannot find autodiscovery xml\n";
  }  

  if(-f "board_spec.xml") {
    $pkg->set_file('.acl.board_spec.xml',"board_spec.xml")
      or mydie("Can't save boardspec.xml into package file: $acl::Pkg::error\n");
  } else {
     print "Cannot find board spec xml\n";
  } 

  if(-f "kernel_arg_info.xml") {
    $pkg->set_file('.acl.kernel_arg_info.xml',"kernel_arg_info.xml");
    unlink 'kernel_arg_info.xml' unless $save_temps;
  } else {
     print "Cannot find kernel arg info xml.\n" if $verbose;
  }

  my $compilation_env = compilation_env_string($work_dir,$board_variant,$all_aoc_args,$bsp_flow_name);
  save_pkg_section($pkg,'.acl.compilation_env',$compilation_env);

  if ($incremental) {
    if ($run_change_detection) {
      acl::Incremental::generate_change_detection_report("$input_dir/reports/lib/json/area.json", "reports/lib/json/area.json", "partitions.diff");
    } else {
      acl::Incremental::generate_initial_compile_report("reports/lib/json/area.json");
    }
    warn $acl::Incremental::warning if (defined $acl::Incremental::warning  && !$quiet_mode);
  }
  remove_named_files("preserved_bundles.txt") unless $save_temps;
  remove_named_files("partitions.diff") unless $save_temps;

  print "$prog: First stage compilation completed successfully.\n" if $verbose;
  # Compute aoc runtime WITHOUT Quartus time or integration, since we don't control that
  my $stage1_end_time = time();
  log_time ("first compilation stage", $stage1_end_time - $stage1_start_time);

  if ($incremental && -e "prev") {
    acl::File::remove_tree("prev")
      or mydie("Cannot remove files under temporary directory prev: $!\n");
  }

  if ( $verilog_gen_only || $accel_gen_flow ) { return; }

  &$finalize();
#aoc: Adding SEARCH_PATH assignment to /data/thoffner/trees/opencl/p4/regtest/opencl/aoc/aoc_flow/test/gurka/top.qsf

  my $file_name = "$base.aoco";
  if ( $output_file_arg ) {
      $file_name = $output_file_arg;
  }
  print "$prog: To compile this project, run \"$prog $file_name\"\n" if $verbose && $compile_step;
}

sub compile_design {
  my ($base,$work_dir,$obj,$x_file,$board_variant,$all_aoc_args,$bsp_flow_name) = @_;
  $fulllog = "$base.log"; #definition moved to global space
  my $pkgo_file = $obj; # Should have been created by first phase.
  my $pkg_file_final = $output_file || acl::File::abs_path("$base.aocx");
  $pkg_file = $pkg_file_final.".tmp";
  # copy partition file if it exists
  acl::File::copy( $save_partition_file, $work_dir."/saved_partitions.txt" ) if $save_partition_file ne '';
  acl::File::copy( $set_partition_file, $work_dir."/set_partitions.txt" ) if $set_partition_file ne '';

  # OK, no turning back remove the result file, so no one thinks we succedded
  unlink $pkg_file_final;
  #Create the new direcory verbatim, then rewrite it to not contain spaces
  $work_dir = $work_dir;

  # To support relative BSP paths, access this before changing dir
  my $postqsys_script = acl::Env::board_post_qsys_script();

  chdir $work_dir or mydie("Can't change dir into $work_dir: $!");

  # First, look in the pkg file to see if there were virtual fabric binaries
  # If there are, that means the previous compile was a vfabric run, and 
  # there is no hardware to build
  acl::File::copy( $pkgo_file, $pkg_file )
   or mydie("Can't copy binary package file $pkgo_file to $pkg_file: $acl::File::error");
  my $pkg = get acl::Pkg($pkg_file)
     or mydie("Can't find package file: $acl::Pkg::error\n");

  #Remember the reason we are here, can't query pkg_file after rename
  my $emulator = $pkg->exists_section('.acl.emulator_object.linux') ||
      $pkg->exists_section('.acl.emulator_object.windows');

  # Store a random hash, and the inputs to quartus hash, in pkg. Should be added before quartus adds new HDL files to the working dir.
  add_hash_sections($work_dir,$board_variant,$pkg_file,$all_aoc_args,$bsp_flow_name);

  my $block_migrations_csv = join(',', @blocked_migrations);
  my $add_migrations_csv = join(',', @additional_migrations);
  if ( ! $no_automigrate && ! $emulator) {
    acl::Board_migrate::migrate_platform_preqsys($bsp_flow_name,$add_migrations_csv,$block_migrations_csv);
  }

  # Set version again, for informational purposes.
  # Do it again, because the second half flow is more authoritative
  # about the executable contents of the package file.
  save_pkg_section($pkg,'.acl.version',acl::Env::sdk_version());

  if (($pkg->exists_section('.acl.vfabric') && 
      $pkg->exists_section('.acl.fpga.bin')) ||
      $pkg->exists_section('.acl.emulator_object.linux') ||
     $pkg->exists_section('.acl.emulator_object.windows'))
  {
     unlink( $pkg_file_final ) if -f $pkg_file_final;
     rename( $pkg_file, $pkg_file_final )
       or mydie("Can't rename $pkg_file to $pkg_file_final: $!");

     if (!$emulator) {
         print "Rapid Prototyping flow is successful.\n" if $verbose;
     } else {
   print "Emulator flow is successful.\n" if $verbose;
   print "To execute emulated kernel, invoke host with \n\tenv CL_CONTEXT_EMULATOR_DEVICE_INTELFPGA=1 <host_program>\n For multi device emulations replace the 1 with the number of devices you wish to emulate\n" if $verbose;

     }
     return;
  }

  # print the message to indicate long processing time
  if ($new_sim_mode) {
    print "Compiling for Simulator.\n" if (!$quiet_mode);
  } else {
  print "Compiling for FPGA. This process may take a long time, please be patient.\n" if (!$quiet_mode);
  }

  # If we have the vfabric section, but not the bin section, then
  # we are doing a vfabric compile
  if ($pkg->exists_section('.acl.vfabric') && 
      !$pkg->exists_section('.acl.fpga.bin')) {
    $generate_vfabric = 1;
  }

  if ( ! $skip_qsys) { 

    #Ignore SOPC Builder's return value
    my $sopc_builder_cmd = "qsys-script";
    my $ip_gen_cmd = 'qsys-generate';

    # Make sure both qsys-script and ip-generate are on the command line
    my $qsys_location = acl::File::which_full ("qsys-script"); chomp $qsys_location;
    if ( not defined $qsys_location ) {
       mydie ("Error: qsys-script executable not found!\n".
              "Add quartus bin directory to the front of the PATH to solve this problem.\n");
    }
    my $ip_gen_location = acl::File::which_full ("ip-generate"); chomp $ip_gen_location;
        
    # Run Java Runtime Engine with max heap size 512MB, and serial garbage collection.
    my $jre_tweaks = "-Xmx512M -XX:+UseSerialGC";

    my $windows_longpath_flag = 0;
    open LOG, "<sopc.tmp";
    while (my $line = <LOG>) {
      if ($line =~ /Error\s*(?:\(\d+\))?:/) {
        print $line;
        # Is this a windows long-path issue?
        $windows_longpath_flag = 1 if win_longpath_error_quartus($line);
      }
    }
    print $win_longpath_suggest if ($windows_longpath_flag and isWindowsOS());
    close LOG;

    # Parse the board spec for information on how the system is built
    my $version = ::acl::Env::aocl_boardspec( ".", "version".$bsp_flow_name);
    my $generic_kernel = ::acl::Env::aocl_boardspec( ".", "generic_kernel".$bsp_flow_name);
    my $qsys_file = ::acl::Env::aocl_boardspec( ".", "qsys_file".$bsp_flow_name);
    my $project = ::acl::Env::aocl_boardspec( ".", "project".$bsp_flow_name);
    ( $version.$generic_kernel.$qsys_file.$project !~ /error/ ) or mydie("BSP compile-flow $bsp_flow_name not found\n" );

    # Simulation flow overrides
    if($new_sim_mode) {
      $project = "none";
      $generic_kernel = 1;
      $qsys_file = "none";
      $postqsys_script = "";
    }

    # Handle the new Qsys requirement for a --quartus-project flag from 16.0 -> 16.1
    my $qsys_quartus_project = ( $QUARTUS_VERSION =~ m/Version 16\.0/ ) ? "" : "--quartus-project=$project";

    # Build the kernel Qsys system
    if ( $generic_kernel or ($version eq "0.9" and -e "base.qsf")) 
    {
      $return_status = mysystem_full(
        {'time' => 1, 'time-label' => 'sopc builder', 'stdout' => 'sopc.tmp', 'stderr' => '&STDOUT'},
        "$sopc_builder_cmd $qsys_quartus_project --script=kernel_system.tcl $jre_tweaks" );
      move_to_log("!=========Qsys kernel_system script===========", "sopc.tmp", $fulllog);
      $return_status == 0 or  mydie("Qsys-script FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
      if (!($qsys_file eq "none"))
      {
        $return_status =mysystem_full(
          {'time' => 1, 'time-label' => 'sopc builder', 'stdout' => 'sopc.tmp', 'stderr' => '&STDOUT'},
          "$sopc_builder_cmd $qsys_quartus_project --script=system.tcl $jre_tweaks --system-file=$qsys_file" );
        move_to_log("!=========Qsys system script===========", "sopc.tmp", $fulllog);
        $return_status == 0 or  mydie("Qsys-script FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
      }
    } else {
      $return_status = mysystem_full(
        {'time' => 1, 'time-label' => 'sopc builder', 'stdout' => 'sopc.tmp', 'stderr' => '&STDOUT'},
        "$sopc_builder_cmd $qsys_quartus_project --script=system.tcl $jre_tweaks --system-file=$qsys_file" );
      move_to_log("!=========Qsys script===========", "sopc.tmp", $fulllog);
      $return_status == 0 or  mydie("Qsys-script FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
    }

    # Generate HDL from the Qsys system
    if ($new_sim_mode) {
      # Create the  complete simulation system
      print "Creating simulation system...\n" if $verbose && !$quiet_mode;
      my $generate_system_script = 'aoc_generate_msim_system.tcl';
      generate_msim_system_tcl($generate_system_script);
      $return_status = mysystem_full( 
        {'time' => 1, 'time-label' => 'qsys-script-simulation, ', 'stdout' => 'qsys-script.tmp', 'stderr' => '&STDOUT'},
        "$sopc_builder_cmd --script=$generate_system_script $qsys_quartus_project");
      move_to_log("!=========create-simulation===========","qsys-script.tmp",$fulllog);
      $return_status == 0 or mydie("Simulation system creation FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
      # Generate the simulatable HDL
      print "Generating simulation system...\n" if $verbose && !$quiet_mode;
      my $project = $is_pro_mode ? $qsys_quartus_project : '';

      my $devicemodel = uc acl::Env::aocl_boardspec( ".", "devicemodel");
      ($devicemodel) = $devicemodel =~ /(.*)_.*/;
      my $devicefamily = device_get_family_no_normalization($devicemodel);
      $return_status = mysystem_full( 
        {'time' => 1, 'time-label' => 'qsys-generate-simulation, ', 'stdout' => 'ipgen.tmp', 'stderr' => '&STDOUT'},
        "$ip_gen_cmd --family=\"$devicefamily\" msim_sim.qsys --simulation $project --jvm-max-heap-size=3G --clear-output-directory");
      $return_status == 0 or mydie("Simulation system generation FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
    } elsif ($simulation_mode) {
      print "Qsys ip-generate (simulation mode) started!\n" ;      
      $return_status = mysystem_full( 
        {'time' => 1, 'time-label' => 'ip generate (simulation), ', 'stdout' => 'ipgen.tmp', 'stderr' => '&STDOUT'},
      "$ip_gen_cmd --component-file=$qsys_file --file-set=SIM_VERILOG --component-param=CALIBRATION_MODE=Skip  --output-directory=system/simulation --report-file=sip:system/simulation/system.sip --jvm-max-heap-size=3G" );                           
      print "Qsys ip-generate done!\n" ;            
    } else {      
      my $generate_cmd = ::acl::Env::aocl_boardspec( ".", "generate_cmd".$bsp_flow_name);
      ( $generate_cmd !~ /error/ ) or mydie("BSP compile-flow $bsp_flow_name not found\n");
      $return_status = mysystem_full( 
        {'time' => 1, 'time-label' => 'ip generate', 'stdout' => 'ipgen.tmp', 'stderr' => '&STDOUT'},
        "$generate_cmd" );  
    }
    # Check the log file for errors
    my $windows_longpath_flag = 0;
    open LOG, "<ipgen.tmp";
    while (my $line = <LOG>) {
      if ($line =~ /Error\s*(?:\(\d+\))?:/) {
        print $line;
        # Is this a windows long-path issue?
        $windows_longpath_flag = 1 if win_longpath_error_quartus($line);
      }
    }
    print $win_longpath_suggest if ($windows_longpath_flag and isWindowsOS());
    close LOG;
    move_to_log("!=========ip-generate===========","ipgen.tmp",$fulllog);
    $return_status == 0 or mydie("ip-generate FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");

    # Some boards may post-process qsys output
    if (defined $postqsys_script and $postqsys_script ne "") {
      mysystem( "$postqsys_script" ) == 0 or mydie("Couldn't run postqsys-script for the board!\n");
    }
    print_bsp_msgs($fulllog);
  }

  # For simulation flow, compile the simulation, package it into the aocx, and then exit
  if($new_sim_mode) {
    # Generate compile and run scripts
    generate_simulation_scripts();
    # Compile the simulation
    print "Compiling simulation...\n" if $verbose && !$quiet_mode;
    my $msim_compile_script = 'msim_sim/sim/msim_compile.tcl';
    $return_status = mysystem_full( 
      {'time' => 1, 'time-label' => 'compiling-simulation, ', 'stdout' => 'msim-compile.tmp', 'stderr' => '&STDOUT'},
      "vsim -batch -do \"$msim_compile_script\"");
    move_to_log("!=========msim-compile===========","msim-compile.tmp",$fulllog);
    $return_status == 0 or mydie("Simulation compile FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
    print "Simulation generation done!\n" unless $quiet_mode;
    # Bundle up the simulation directory
    $return_status = $pkg->package('fpga-sim.bin', 'sys_description.hex', 'msim_sim', 'ip');
    $return_status == 0 or mydie("Bundling simulation files FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
    $pkg->set_file(".acl.fpga.bin","fpga-sim.bin");
    unlink("fpga-sim.bin");
    # Remove the generated verilog.
    if (!$save_temps) {
      acl::File::remove_tree("msim_sim")
        or mydie("Cannot remove files under temporary directory msim_sim: $!\n");
    }
    print "Simulation flow completed successfully.\n" if $verbose;

    # Move temporary file to final location.
    unlink( $pkg_file_final ) if -f $pkg_file_final;
    rename( $pkg_file, $pkg_file_final )
      or mydie("Can't rename $pkg_file to $pkg_file_final: $!");
    return;
  }

  # Override the fitter seed, if specified.
  if ( $fit_seed ) {
    my @designs = acl::File::simple_glob( "*.qsf" );
    $#designs > -1 or mydie ("Internal Compiler Error.  Seed argument was passed but could not find any qsf files\n");
    foreach (@designs) {
      my $qsf = $_;
      $return_status = mysystem( "echo \"\nset_global_assignment -name SEED $fit_seed\n\" >> $qsf" );
    }
  }

  # Add DSP location constraints, if specified.
  if ( $dsploc ) {
    extract_atoms_from_postfit_netlist($base,$dsploc,"DSP",$bsp_flow_name);
  } 

  # Add RAM location constraints, if specified.
  if ( $ramloc ) {
    extract_atoms_from_postfit_netlist($base,$ramloc,"RAM",$bsp_flow_name); 
  } 

  if ( $ip_gen_only ) { return; }

  # "Old --hw" starting point
  my $project = ::acl::Env::aocl_boardspec( ".", "project".$bsp_flow_name);
  ( $project !~ /error/ ) or mydie("BSP compile-flow $bsp_flow_name not found\n");
  my @designs = acl::File::simple_glob( "$project.qpf" );
  $#designs >= 0 or mydie ("Internal Compiler Error.  BSP specified project name $project, but $project.qpf does not exist.\n");
  $#designs == 0 or mydie ("Internal Compiler Error.\n");
  my $design = shift @designs;

  my $synthesize_cmd = ::acl::Env::aocl_boardspec( ".", "synthesize_cmd".$bsp_flow_name);
  ( $synthesize_cmd !~ /error/ ) or mydie("BSP compile-flow $bsp_flow_name not found\n");

  my $retry = 0;
  my $MAX_RETRIES = 3;
  if ($high_effort) {
    print "High-effort hardware generation selected, compile time may increase signficantly.\n";
  }

  do {

    if (defined $ENV{ACL_QSH_COMPILE_CMD})
    {
      # Environment variable ACL_QSH_COMPILE_CMD can be used to replace default
      # quartus compile command (internal use only).  
      my $top = acl::File::mybasename($design); 
      $top =~ s/\.qpf//;
      my $custom_cmd = $ENV{ACL_QSH_COMPILE_CMD};
      $custom_cmd =~ s/PROJECT/$top/;
      $custom_cmd =~ s/REVISION/$top/;
      $return_status = mysystem_full(
        {'time' => 1, 'time-label' => 'Quartus compilation', 'stdout' => $quartus_log},
        $custom_cmd);
    } else {
      $return_status = mysystem_full(
        {'time' => 1, 'time-label' => 'Quartus compilation', 'stdout' => $quartus_log, 'stderr' => 'quartuserr.tmp'},
        $synthesize_cmd);
    }

    print_bsp_msgs($quartus_log);

    if ( $return_status != 0 ) {
      if ($high_effort && hard_routing_error($quartus_log) && $retry < $MAX_RETRIES) {
        print " kernel fitting error encountered - retrying aocx compile.\n";
        $retry = $retry + 1;

        # Override the fitter seed, if specified.
        my @designs = acl::File::simple_glob( "*.qsf" );
        $#designs > -1 or print_quartus_errors($quartus_log, 0);
        my $seed = $retry * 10;
        foreach (@designs) {
          my $qsf = $_;
          if ($retry > 1) {
            # Remove the old seed setting
            open( my $read_fh, "<", $qsf ) or mydie("Unexpected Compiler Error, not able to generate hardware in high effort mode.");
            my @file_lines = <$read_fh>; 
            close( $read_fh ); 

            open( my $write_fh, ">", $qsf ) or mydie("Unexpected Compiler Error, not able to generate hardware in high effort mode.");
            foreach my $line ( @file_lines ) { 
              print {$write_fh} $line unless ( $line =~ /set_global_assignment -name SEED/ ); 
            } 
            print {$write_fh} "set_global_assignment -name SEED $seed\n";
            close( $write_fh ); 
          } else {
            $return_status = mysystem( "echo \"\nset_global_assignment -name SEED $seed\n\" >> $qsf" );
          }
        }
      } else {
        $retry = 0;
        print_quartus_errors($quartus_log, $high_effort == 0);
      }
    } else {
      $retry = 0;
    }
  } while ($retry && $retry < $MAX_RETRIES);

  # postcompile migration
  if( ! $no_automigrate && ! $emulator ) {
    acl::Board_migrate::migrate_platform_postcompile($bsp_flow_name,$add_migrations_csv,$block_migrations_csv);
  }

  # check sta log for timing not met warnings
  print "$prog: Hardware generation completed successfully.\n" if $verbose;

  my $fpga_bin = 'fpga.bin';
  if ( -f $fpga_bin ) {
    $pkg->set_file('.acl.fpga.bin',$fpga_bin)
       or mydie("Can't save FPGA configuration file $fpga_bin into package file: $acl::Pkg::error\n");

    if ($generate_vfabric) { # need to save this to the board path
        my $acl_board_hw_path= get_acl_board_hw_path($board_variant);
        my $vfab_lib_path = (($custom_vfab_lib_path) ? $custom_vfab_lib_path : 
              $acl_board_hw_path."_vfabric");
        my $num_templates_file = "$vfab_lib_path/num_templates.txt";
        my $dir_writeable = 1;
        my $var_id = 0;

        # create the directory if necessary
        if (!-f $num_templates_file) { 
           $dir_writeable = acl::File::make_path($vfab_lib_path);
           if ($dir_writeable) {
              $dir_writeable = open (VFAB_NUM_TMP_FILE, '>', $num_templates_file);
              if ($dir_writeable) {
                 print VFAB_NUM_TMP_FILE "$var_id\n";
                 close VFAB_NUM_TMP_FILE;
              }
           }
        } else { #templates file already exist: read variant number
          open VFAB_NUM_TMP_FILE, "<$num_templates_file" or mydie("Invalid template directory");
          $var_id = <VFAB_NUM_TMP_FILE>;
          chomp($var_id);
          close VFAB_NUM_TMP_FILE;
        }
        $var_id++;

        if (!$reuse_vfabrics && open (VFAB_NUM_TMP_FILE, '>', $num_templates_file)) {
          acl::File::copy( "vfab_var1.txt", $vfab_lib_path."/var".$var_id.".txt" )
            or mydie("Can't copy created template vfab_var1.txt to $vfab_lib_path/var$var_id.txt: $acl::File::error");
          acl::File::copy( $fpga_bin, $vfab_lib_path."/var".$var_id.".fpga.bin" )
            or mydie("Can't copy created template fpga.bin to $vfab_lib_path/var$var_id.fpga.bin: $acl::File::error");
          acl::File::copy( "acl_quartus_report.txt", $vfab_lib_path."/var".$var_id.".acl_quartus_report.txt" )
            or mydie("Can't copy created template acl_quartus_report.txt to $vfab_lib_path/var$var_id.acl_quartus_report.txt: $acl::File::error");
          if (! -f "$vfab_lib_path./sys_description.txt") {
             acl::File::copy( "sys_description.txt", $vfab_lib_path."/sys_description.txt" )
               or mydie("Can't copy sys_description.txt to $vfab_lib_path/sys_description.txt: $acl::File::error");
          }

          print "Successfully created Rapid Prototyping Template $var_id\n";

          save_vfabric_files_to_pkg($pkg, $var_id, $vfab_lib_path, ".", $board_variant);

    # update the number of templates there are in the directory
          print VFAB_NUM_TMP_FILE $var_id;
          close VFAB_NUM_TMP_FILE;
        } else {
          print "Cannot save generated Rapid Prototyping Template to directory $vfab_lib_path. May not have write permissions.\n\n";
          print "To reuse this Template in a future kernel compile, please manually save the following files:\n";
          print " - vfab_var1.txt as $vfab_lib_path"."/var".$var_id.".txt\n";
          print " - fpga.bin as $vfab_lib_path"."/var".$var_id.".fpga.bin\n";
          print " - acl_quartus_report.txt as $vfab_lib_path"."/var".$var_id.".acl_quartus_report.txt\n";
          print " - sys_description.txt as $vfab_lib_path"."/sys_description.txt if missing\n";
          print "\nPlease increment ".$vfab_lib_path."/num_templates.txt to include this Template\n";
        }
    }

  } else { #If fpga.bin not found, package up sof and core.rbf

    # Save the SOF in the package file.
    my @sofs = (acl::File::simple_glob( "*.sof" ));
    if ( $#sofs < 0 ) {
      print "$prog: Warning: Cannot find a FPGA programming (.sof) file\n";
    } else {
      if ( $#sofs > 0 ) {
        print "$prog: Warning: Found ".(1+$#sofs)." FPGA programming files. Using the first: $sofs[0]\n";
      }
      $pkg->set_file('.acl.sof',$sofs[0])
        or mydie("Can't save FPGA programming file into package file: $acl::Pkg::error\n");
    }
    # Save the RBF in the package file, if it exists.
    # Sort by name instead of leaving it random.
    # Besides, sorting will pick foo.core.rbf over foo.periph.rbf
    foreach my $rbf_type ( qw( core periph ) ) {
      my @rbfs = sort { $a cmp $b } (acl::File::simple_glob( "*.$rbf_type.rbf" ));
      if ( $#rbfs < 0 ) {
        #     print "$prog: Warning: Cannot find a FPGA core programming (.rbf) file\n";
      } else {
        if ( $#rbfs > 0 ) {
          print "$prog: Warning: Found ".(1+$#rbfs)." FPGA $rbf_type.rbf programming files. Using the first: $rbfs[0]\n";
        }
        $pkg->set_file(".acl.$rbf_type.rbf",$rbfs[0])
          or mydie("Can't save FPGA $rbf_type.rbf programming file into package file: $acl::Pkg::error\n");
      }
    }
  }

  my $pll_config = 'pll_config.bin';
  if ( -f $pll_config ) {
    $pkg->set_file('.acl.pll_config',$pll_config)
       or mydie("Can't save FPGA clocking configuration file $pll_config into package file: $acl::Pkg::error\n");
  }

  my $acl_quartus_report = 'acl_quartus_report.txt';
  if ( -f $acl_quartus_report ) {
    $pkg->set_file('.acl.quartus_report',$acl_quartus_report)
       or mydie("Can't save Quartus report file $acl_quartus_report into package file: $acl::Pkg::error\n");
  }

  unlink( $pkg_file_final ) if -f $pkg_file_final;
  rename( $pkg_file, $pkg_file_final )
    or mydie("Can't rename $pkg_file to $pkg_file_final: $!");

  if ((! $incremental || ! -e "prev") && ! $save_temps) {
    acl::File::remove_tree("prev")
      or mydie("Cannot remove files under temporary directory prev: $!\n");
  }

  chdir $orig_dir or mydie("Can't change back into directory $orig_dir: $!");
  remove_intermediate_files($work_dir,$pkg_file_final) if $tidy;
}

# Some aoc args translate to args to many underlying exes.
sub process_meta_args {
  my ($cur_arg, $argv) = @_;
  my $processed = 0;
  if ($cur_arg eq '--1x-clock-for-local-mem') {
    # TEMPORARY: don't actually enforce this flag
    #$opt_arg_after .= ' -force-1x-clock-local-mem';
    #$llc_arg_after .= ' -force-1x-clock-local-mem';
    #$sysinteg_arg_after .= ' --cic-1x-local-mem';
    $processed = 1;
  }
  elsif ( ($cur_arg eq '--sw_dimm_partition') or ($cur_arg eq '--sw-dimm-partition')) {
    # TODO need to do this some other way
    # this flow is incompatible with the dynamic board selection (--board)
    # because it overrides the board setting
    $sysinteg_arg_after .= ' --cic-global_no_interleave ';
    $llc_arg_after .= ' -use-swdimm';
    $processed = 1;
  }

  return $processed;
}

# Deal with multiple specified source files
sub process_input_file_arguments {

  if ($#given_input_files == -1) {
    # No input files are given
    return "";
  }

  # Only multiple .cl files are allowed. Can't mix
  # .aoco and .cl, for example.  
  my %suffix_cnt;
  foreach my $gif (@given_input_files) {
    my $suffix = $gif;
    $suffix =~ s/.*\.//;
    $suffix =~ tr/A-Z/a-z/;
    $suffix_cnt{$suffix}++;
  }

  # Error checks, even for one file
    
  if ($suffix_cnt{'c'} > 0 and !($soft_ip_c_flow || $c_acceleration)) {
    # Pretend we never saw it i.e. issue the same message as we would for 
    # other not recognized extensions. Not the clearest message, 
    # but at least consistent
    mydie("No recognized input file format on the command line");
  }
  
  # If have multiple files, they should all be .cl files.
  if ($#given_input_files > 0 and ($suffix_cnt{'cl'} < $#given_input_files-1)) {
    # Have some .cl files but not ALL .cl files. Not allowed.
    mydie("If multiple input files are specified, all must be .cl files.\n");
  }
  
  # Make sure aoco file is not an HDL component package
  if ($suffix_cnt{'aoco'} > 0) {
    # At this point, know that have a single input file.
    system(acl::Env::sdk_pkg_editor_exe(), $given_input_files[0], 'exists', '.comp_header');
    if ($? == 0) {
      mydie("Specified aoco file is a HDL component package. It cannot be used by itself to do hardware compiles!\n");
    }
  }

  # For emulation flow, if library(ies) are specified, 
  # extract all C model files and add them to the input file list.
  if ($emulator_flow and $#resolved_lib_files > -1) {
    
    # C model files from libraries will be extracted to this folder
    my $c_model_folder = ".emu_models";
    
    # If it already exists, clean it out.
    if (-d $c_model_folder) {
      chdir $c_model_folder or die $!;
        opendir (DIR, ".") or die $!;
        while (my $file = readdir(DIR)) {
          if ($file ne "." and $file ne "..") {
            unlink $file;
          }
        }
        closedir(DIR);
      chdir ".." or die $!;
    } else {
      mkdir $c_model_folder or die $!;
    }
    
    my @c_model_files;
    foreach my $libfile (@resolved_lib_files) {
      my $new_files = `$aocl_libedit_exe extract_c_models \"$libfile\" $c_model_folder`;
      push @c_model_files, split /\n/, $new_files;
    }
    
    # Add library files to the front of file list.
    if ($verbose) {
      print "All OpenCL C models were extracted from specified libraries and added to compilation\n";
    }
    @given_input_files = (@c_model_files, @given_input_files);
  }
  
  
  my $gathering_fname = "__all_sources.cl";
  if ($#given_input_files == 0) {
    # Only one input file, don't bother grouping
    $gathering_fname = $given_input_files[-1]; 
  } else {
    if ($verbose) {
      print "All input files will be grouped into one by $gathering_fname\n";
    }
    open (my $out, ">", $gathering_fname) or die "Couldn't create a file \"$gathering_fname\"!\n";
    foreach my $gif (@given_input_files) {
      -e $gif or mydie("Specified input file $gif does not exist.\n");
      print $out "#include \"$gif\"\n";
    }
    close $out;
  }
  
  # Make 'base' name for all naming purposes (subdir, aoco/aocx files) to 
  # be based on the last source file. Otherwise, it will be __all_sources, 
  # which is unexpected.
  my $last_src_file = $given_input_files[-1];
  
  return ($gathering_fname, acl::File::mybasename($last_src_file));
}


sub populate_installed_packages {
   if (!(-e $installed_bsp_list_file) or !(-f $installed_bsp_list_file)) {
     return;
   }

   # read all the installed packages
   unless(open FILE, '<'.$installed_bsp_list_file) {
     die "Unable to open $installed_bsp_list_file\n";
   }
   # Note, if the file is being modified at the same time, by a different tool, we may read garbage here.
   @installed_packages = <FILE>;
   chomp(@installed_packages);
   close FILE;
}

sub populate_boards {
  populate_installed_packages();

  # if not bsps installed, use AOCL_BOARD_PACKAGE_ROOT
  if  ($#installed_packages < 0) {
    my $default_bsp = acl::Board_env::get_board_path();
    push @installed_packages, $default_bsp;
  }

  foreach my $bsp (@installed_packages) {
    $ENV{'AOCL_BOARD_PACKAGE_ROOT'} = $bsp;
    my %boards = acl::Env::board_hw_list();
    for my $b ( sort keys %boards ) {
      my $boarddir = $boards{$b};
      $board_boarddir_map{"$b;$bsp"} = $boarddir;
    }
  }
}

# List installed boards.
sub list_boards {
  populate_boards();

  print "Board list:\n";

  if( keys( %board_boarddir_map ) == -1 ) {
    print "  none found\n";
  } else {
      for my $b ( sort keys %board_boarddir_map ) {
      my $boarddir = $board_boarddir_map{$b};
      my ($name,$bsp) = split(';',$b);
      print "  $name\n";
      print "     Board Package: $bsp\n";
      if ( ::acl::Env::aocl_boardspec( $boarddir, "numglobalmems") > 1 ) {
        my $gmemnames = ::acl::Env::aocl_boardspec( $boarddir, "globalmemnames");
        print "     Memories:      $gmemnames\n";
      }
      my $channames = ::acl::Env::aocl_boardspec( $boarddir, "channelnames");
      if ( length $channames > 0 ) {
        print "     Channels:      $channames\n";
      }
      print "\n";
    }
  }
}


sub usage() {
  my $default_board_text;
  my $board_env = &acl::Board_env::get_board_path() . "/board_env.xml";

  if (-e $board_env) {
    my $default_board;
    ($default_board) = &acl::Env::board_hardware_default();
    $default_board_text = "Default is $default_board.";
  } else {
    $default_board_text = "Cannot find default board location or default board name.";
  }
  print <<USAGE;

aoc -- Intel(R) FPGA SDK for OpenCL(TM) Kernel Compiler

Usage: aoc <options> <file>.[cl|aoco]

Example:
       # First generate an <file>.aoco file
       aoc -c mykernels.cl
       # Now compile the project into a hardware programming file <file>.aocx.
       aoc mykernels.aoco
       # Or generate all at once
       aoc mykernels.cl

Outputs:
       <file>.aocx and/or <file>.aoco

Help Options:
-version
          Print out version infomation and exit

-v        
          Verbose mode. Report progress of compilation

-q
          Quiet mode. Progress of compilation is not reported

-report  
          Print area estimates to screen after intial 
          compilation. The report is always written to the log file.

-h
-help    
          Show this message

Overall Options:
-c        
          Stop after generating a <file>.aoco

-o <output> 
          Use <output> as the name for the output.
          If running with the '-c' option the output file extension should be '.aoco'.
          Otherwise the file extension should be '.aocx'.
          If neither extension is specified, the appropriate extension will be added automatically.

-march=emulator
          Create kernels that can be executed on x86

-g        
          Add debug data to kernels. Also, makes it possible to symbolically
          debug kernels created for the emulator on an x86 machine (Linux only).
          This behavior is enabled by default. This flag may be used to override the -g0 flag.

-g0        
          Don't add debug data to kernels.

-profile(=<all|autorun|enqueued>)
          Enable profile support when generating aocx file:
          all: profile all kernels.
          autorun: profile only autorun kernels.
          enqueued: profile only non-autorun kernels.
          If there is no argument provided, then the mode defaults to 'all'.
          Note that this does have a small performance penalty since profile
          counters will be instantiated and take some FPGA resources.
    
-shared
          Compile OpenCL source file into an object file that can be included into
          a library. Implies -c. 

-I <directory> 
          Add directory to header search path.
          
-L <directory>
          Add directory to OpenCL library search path.
          
-l <library.aoclib>
          Specify OpenCL library file.

-D <name> 
          Define macro, as name=value or just name.

-W        
          Suppress warning.

-Werror   
          Make all warnings into errors.

-library-debug 
          Generate debug output related to libraries.

Modifiers:
-board=<board name>
          Compile for the specified board. $default_board_text

-list-boards
          Print a list of available boards and exit.

-bsp-flow=<flow name>
          Specify the bsp compilation flow by name. If none given, the board's
          default flow is used.

Optimization Control:

-no-interleaving=<global memory name>
          Configure a global memory as separate address spaces for each
          DIMM/bank.  User should then use the Altera specific cl_mem_flags
          (E.g.  CL_CHANNEL_2_INTELFPGA) to allocate each buffer in one DIMM or
          the other. The argument 'default' can be used to configure the default
          global memory. Consult your board's documentation for the memory types
          available. See the Best Practices Guide for more details.

-const-cache-bytes=<N>
          Configure the constant cache size (rounded up to closest 2^n).
    If none of the kernels use the __constant address space, this 
    argument has no effect. 

-fp-relaxed
          Allow the compiler to relax the order of arithmetic operations,
          possibly affecting the precision

-fpc 
          Removes intermediary roundings and conversions when possible, 
          and changes the rounding mode to round towards zero for 
          multiplies and adds

-fast-compile
          Compiles the design with reduced effort for a faster compile time but
          reduced fmax and lower power efficiency. Compiled aocx should only be
          used for internal development and not for deploying in final product.

-high-effort
          Increases aocx compile effort to improve ability to fit
    kernel on the device.

-emulator-channel-depth-model=<default|strict|ignore-depth>
          Controls the depths of channels used by the emulator:
          default: Channels with explicitly-specified depths will use the specified depths.
                   Channels with unspecified depths will use a depth >10000.
          strict: As default except channels of unspecified depth will use a depth of 1.
          ignore-depth: All channels will use a depth >10000.

-cl-single-precision-constant
-cl-denorms-are-zero
-cl-opt-disable
-cl-strict-aliasing
-cl-mad-enable
-cl-no-signed-zeros
-cl-unsafe-math-optimizations
-cl-finite-math-only
-cl-fast-relaxed-math
           OpenCL required options. See OpenCL specification for details


USAGE
#-initial-dir=<dir>
#          Run the parser from the given directory.  
#          The default is to run the parser in the current directory.

#          Use this option to properly resolve relative include 
#          directories when running the compiler in a directory other
#          than where the source file may be found.
#-save-extra
#          Save kernel program source, optimized intermediate representation,
#          and Verilog into the program package file.
#          By default, these items are not saved.
#
#-no-env-check
#          Skip environment checks at startup.
#          Use this option to save a few seconds of runtime if you 
#          already know the environment is set up to run the Intel(R) FPGA SDK
#          for OpenCL(TM) compiler.
#-dot
#          Dump out DOT graph of the kernel pipeline.

}


sub powerusage() {
  print <<POWERUSAGE;

aoc -- Intel(R) FPGA SDK for OpenCL(TM) Kernel Compiler

Usage: aoc <options> <file>.[cl|aoco]

Help Options:

-powerhelp    
          Show this message

Modifiers:
-seed=<value>
          Run the Quartus compile with a seed value of <value>. Default is '1'. 

-dsploc=<compile directory>
          Extract DSP locations from given <compile directory> post-fit netlist and use them in current Quartus compile

-ramloc=<compile directory>
          Extract RAM locations from given <compile directory> post-fit netlist and use them in current Quartus compile

POWERUSAGE

}


sub version($) {
  my $outfile = $_[0];
  print $outfile "Intel(R) FPGA SDK for OpenCL(TM), 64-Bit Offline Compiler\n";
  print $outfile "Version 17.1.0 Build 590\n";
  print $outfile "Copyright (C) 2017 Intel Corporation\n";
}


sub compilation_env_string($$$$){
  my ($work_dir,$board_variant,$input_args,$bsp_flow_name) = @_;
  #Case:354532, not handling relative address for AOCL_BOARD_PACKAGE_ROOT correctly.
  my $starting_dir = acl::File::abs_path('.');  #keeping to change back to this dir after being done.
  chdir $orig_dir or mydie("Can't change back into directory $orig_dir: $!");

  # Gathering all options and tool versions.
  my $acl_board_hw_path= get_acl_board_hw_path($board_variant);
  my $board_spec_xml = find_board_spec($acl_board_hw_path);
  my $platform_type = acl::Env::aocl_boardspec( "$board_spec_xml", "automigrate_type".$bsp_flow_name);
  my $build_number = "590";
  my $acl_Version = "17.1.0";
  my $clang_version = `$clang_exe --version`;
  $clang_version =~ s/\s+/ /g; #replacing all white spaces with space
  my $llc_version = `$llc_exe --version`;
  $llc_version =~ s/\s+/ /g; #replacing all white spaces with space
  my $sys_integrator_version = `$sysinteg_exe --version`;
  $sys_integrator_version =~ s/\s+/ /g; #replacing all white spaces with space
  my $lib_path = "$ENV{'LD_LIBRARY_PATH'}";
  my $board_pkg_root = "$ENV{'AOCL_BOARD_PACKAGE_ROOT'}";
  if (!$QUARTUS_VERSION) {
    $QUARTUS_VERSION = `quartus_sh --version`;
  }
  my $quartus_version = $QUARTUS_VERSION;
  $quartus_version =~ s/\s+/ /g; #replacing all white spaces with space

  # Quartus compile command
  my $synthesize_cmd = ::acl::Env::aocl_boardspec( $acl_board_hw_path, "synthesize_cmd".$bsp_flow_name);
  ( $platform_type.$synthesize_cmd !~ /error/ ) or mydie("BSP compile-flow $bsp_flow_name not found\n");
  my $acl_qsh_compile_cmd="$ENV{'ACL_QSH_COMPILE_CMD'}"; # Environment variable ACL_QSH_COMPILE_CMD can be used to replace default quartus compile command (internal use only).

  # Concatenating everything
  my $res = "";
  $res .= "INPUT_ARGS=".$input_args."\n";
  $res .= "BUILD_NUMBER=".$build_number."\n";
  $res .= "ACL_VERSION=".$acl_Version."\n";
  $res .= "OPERATING_SYSTEM=$^O\n";
  $res .= "BOARD_SPEC_XML=".$board_spec_xml."\n";
  $res .= "PLATFORM_TYPE=".$platform_type."\n";
  $res .= "CLANG_VERSION=".$clang_version."\n";
  $res .= "LLC_VERSION=".$llc_version."\n";
  $res .= "SYS_INTEGRATOR_VERSION=".$sys_integrator_version."\n";
  $res .= "LIB_PATH=".$lib_path."\n";
  $res .= "AOCL_BOARD_PKG_ROOT=".$board_pkg_root."\n";
  $res .= "QUARTUS_VERSION=".$quartus_version."\n";
  $res .= "QUARTUS_OPTIONS=".$synthesize_cmd."\n";
  $res .= "ACL_QSH_COMPILE_CMD=".$acl_qsh_compile_cmd."\n";

  chdir $starting_dir or mydie("Can't change back into directory $starting_dir: $!"); # Changing back to the dir I started with
  return $res;
}

# Addes a unique hash for the compilatin, and a section that contains 3 hashes for the state before quartus compile.
sub add_hash_sections($$$$$) {
  my ($work_dir,$board_variant,$pkg_file,$input_args,$bsp_flow_name) = @_;
  my $pkg = get acl::Pkg($pkg_file) or mydie("Can't find package file: $acl::Pkg::error\n");

  #Case:354532, not handling relative address for AOCL_BOARD_PACKAGE_ROOT correctly.
  my $starting_dir = acl::File::abs_path('.');  #keeping to change back to this dir after being done.
  chdir $orig_dir or mydie("Can't change back into directory $orig_dir: $!");

  my $compilation_env = compilation_env_string($work_dir,$board_variant,$input_args,$bsp_flow_name);

  save_pkg_section($pkg,'.acl.compilation_env',$compilation_env);

  # Random unique hash for this compile:
  my $hash_exe = acl::Env::sdk_hash_exe();
  my $temp_hashed_file="$work_dir/hash.tmp"; # Temporary file that is used to pass in strings to aocl-hash
  my $ftemp;
  my $random_hash_key;
  open($ftemp, '>', $temp_hashed_file) or die "Could not open file $!";
  my $rand_key = rand;
  print $ftemp "$rand_key\n$compilation_env";
  close $ftemp;


  $random_hash_key = `$hash_exe \"$temp_hashed_file\"`;
  unlink $temp_hashed_file;
  save_pkg_section($pkg,'.acl.rand_hash',$random_hash_key);

  # The hash of inputs and options to quartus + quartus versions:
  my $before_quartus;

  my $acl_board_hw_path= get_acl_board_hw_path($board_variant);
  if (!$QUARTUS_VERSION) {
    $QUARTUS_VERSION = `quartus_sh --version`;
  }
  my $quartus_version = $QUARTUS_VERSION;
  $quartus_version =~ s/\s+/ /g; #replacing all white spaces with space

  # Quartus compile command
  my $synthesize_cmd = ::acl::Env::aocl_boardspec( $acl_board_hw_path, "synthesize_cmd".$bsp_flow_name);
  ( $bsp_flow_name !~ /error/ ) or mydie("BSP compile-flow $bsp_flow_name not found\n");
  my $acl_qsh_compile_cmd="$ENV{'ACL_QSH_COMPILE_CMD'}"; # Environment variable ACL_QSH_COMPILE_CMD can be used to replace default quartus compile command (internal use only).

  open($ftemp, '>', $temp_hashed_file) or die "Could not open file $!";
  print $ftemp "$quartus_version\n$synthesize_cmd\n$acl_qsh_compile_cmd\n";
  close $ftemp;

  $before_quartus.= `$hash_exe \"$temp_hashed_file\"`; # Quartus input args hash
  $before_quartus.= `$hash_exe -d \"$acl_board_hw_path\"`; # All bsp directory hash
  $before_quartus.= `$hash_exe -d \"$work_dir\" --filter .v --filter .sv --filter .hdl --filter .vhdl`; # HDL files hash

  unlink $temp_hashed_file;
  save_pkg_section($pkg,'.acl.quartus_input_hash',$before_quartus);
  chdir $starting_dir or mydie("Can't change back into directory $starting_dir: $!"); # Changing back to the dir I started with.
}

sub main {
  my $all_aoc_args="@ARGV";
  my @args = (); # regular args.
  @user_opencl_args = ();
  my $atleastoneflag=0;
  my $dirbase=undef;
  my $board_variant=undef;
  my $bsp_variant=undef;
  my $using_default_board = 0;
  my $bsp_flow_name = undef;
  my $regtest_bak_cache = 0;
  my $input_dir = '';
  my $old_board_package_root = $ENV{'AOCL_BOARD_PACKAGE_ROOT'};
  if (! defined $old_board_package_root) {
    $old_board_package_root = "";
  }
  if (!@ARGV) {
    push @ARGV, qw(-help);
  }
  while (@ARGV) {
    my $arg = shift @ARGV;

    # case:492114 treat options that start with -l as a special case.
    # By putting this code at the top we enforce that all options
    # starting with -l must be added to the l_opts_exclude array or else
    # they won't work because they'll be treated as a library name.
    if ( ($arg =~ m!^-l(\S+)!) ) {
      my $full_opt = '-l' . $1;
      my $excluded = 0;

      # If you add an option that starts with -l you must update the
      # l_opts_exclude list.
      foreach my $opt_name (@acl::Common::l_opts_exclude) {
        if ( ($full_opt =~ m!^$opt_name!) ) {
          # Options on the exclusion list are parsed in the long
          # if/elsif chain below like every other option.
          $excluded = 1;
          last;
        }
      }

      # -l<libname>
      if (!$excluded) {
          push (@lib_files, $1);
          next;
      }
    }

    # -h / -help
    if ( ($arg eq '-h') or ($arg eq '-help') or ($arg eq '--help') ) {
      if ($arg eq '--help') {
        print "Warning: Please use -help instead of --help\n";
      }
      usage(); 
      exit 0; 
    }
    # -powerhelp
    elsif ( ($arg eq '-powerhelp') or ($arg eq '--powerhelp') ) {
      if ($arg eq '--powerhelp') {
        print "Warning: Please use -powerhelp instead of --powerhelp\n";
      }
      powerusage();
      exit 0;
    }
    # -version / -V
    elsif ( ($arg eq '-version') or ($arg eq '-V') or ($arg eq '--version') ) {
      if ($arg eq '--version') {
        print "Warning: Please use -version instead of --version\n";
      }
      version(\*STDOUT);
      exit 0;
    }
    # -list-deps
    elsif ( ($arg eq '-list-deps') or ($arg eq '--list-deps') ) {
      if ($arg eq '--list-deps') {
        print "Warning: Please use -list-deps instead of --list-deps\n";
      }
      print join("\n",values %INC),"\n";
      exit 0;
    }
    # -list-boards
    elsif ( ($arg eq '-list-boards') or ($arg eq '--list-boards') ) {
      if ($arg eq '--list-boards') {
        print "Warning: Please use -list-boards instead of --list-boards\n";
      }
      list_boards();
      exit 0;
    }
    # -v
    elsif ( ($arg eq '-v') ) {
      $verbose += 1;
      if ($verbose > 1) {
        $prog = "#$prog";
      }
    }
    # -q
    elsif ( ($arg eq '-q') ) {
      $quiet_mode = 1;
    }
    # -hw
    elsif ( ($arg eq '-hw') or ($arg eq '--hw') ) {
      if ($arg eq '--hw') {
        print "Warning: Please use -hw instead of --hw\n";
      }
      $run_quartus = 1;
    }
    # -quartus
    elsif ( ($arg eq '-quartus') or ($arg eq '--quartus') ) {
      if ($arg eq '--quartus') {
        print "Warning: Please use -quartus instead of --quartus\n";
      }
      $skip_qsys = 1;
      $run_quartus = 1;
    }
    # -standalone
    elsif ( ($arg eq '-standalone') or ($arg eq '--standalone') ) {
      if ($arg eq '--standalone') {
        print "Warning: Please use -standalone instead of --standalone\n";
      }
      $standalone = 1;
    }
    # -d
    elsif ( ($arg eq '-d') ) {
      $debug = 1;
    }
    # -s
    elsif ( ($arg eq '-s') ) {
      $simulation_mode = 1;
      $ip_gen_only = 1;
      $atleastoneflag = 1;
    }
    # -simulate
    elsif ( ($arg eq '-simulate') or ($arg eq '--simulate') ) {
      if ($arg eq '--simulate') {
        print "Warning: Please use -simulate instead of --simulate\n";
      }
      $new_sim_mode = 1;
      $ip_gen_only = 1;
      $atleastoneflag = 1;
    }
    # -ghdl / -ghdl=<value>
    elsif ($arg =~ /-ghdl(=(\d+))?/) {
      $sim_debug = 1;
      if (defined $2) {
        $sim_debug_depth = $2;
      }
    }
    # -high-effort
    elsif ( ($arg eq '-high-effort') or ($arg eq '--high-effort') ) {
      if ($arg eq '--high-effort') {
        print "Warning: Please use -high-effort instead of --high-effort\n";
      }
      $high_effort = 1;
    }
    # -report
    elsif ( ($arg eq '-report') or ($arg eq '--report') ) {
      if ($arg eq '--report') {
        print "Warning: Please use -report instead of --report\n";
      }
      $report = 1;
    }
    # -g
    elsif ( ($arg eq '-g') ) {
      $dash_g = 1;
      $user_dash_g = 1;
    }
    # -g0
    elsif ( ($arg eq '-g0') ) {
      $dash_g = 0;
    }
    # -profile
    elsif ( ($arg eq '-profile') or ($arg eq '--profile') ) {
      if ($arg eq '--profile') {
        print "Warning: Please use -profile instead of --profile\n";
      }
      print "$prog: Warning: no argument provided for the option -profile, will enable profiling for all kernels by default\n";
      $profile = 'all'; # Default is 'all'
      $save_last_bc = 1;
    }
    # -profile=<name>
    elsif ( $arg =~ /^-profile=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -profile= requires an argument");
      } else {
        $profile = $argument_value;
        if ( !(($profile eq 'all' ) || ($profile eq 'autorun') || ($profile eq 'enqueued')) ) {
          print "$prog: Warning: invalid argument '$profile' for the option --profile, will enable profiling for all kernels by default\n";
          $profile = 'all'; # Default is "all"
        }
        $save_last_bc = 1;
      }
    }
    # -save-extra
    elsif ( ($arg eq '-save-extra') or ($arg eq '--save-extra') ) {
      if ($arg eq '--save-extra') {
        print "Warning: Please use -save-extra instead of --save-extra\n";
      }
      $pkg_save_extra = 1;
    }
    # -no-env-check
    elsif ( ($arg eq '-no-env-check') or ($arg eq '--no-env-check') ) {
      if ($arg eq '--no-env-check') {
        print "Warning: Please use -no-env-check instead of --no-env-check\n";
      }
      $do_env_check = 0;
    }
    # -no-auto-migrate
    elsif ( ($arg eq '-no-auto-migrate') or ($arg eq '--no-auto-migrate') ) {
      if ($arg eq '--no-auto-migrate') {
        print "Warning: Please use -no-auto-migrate instead of --no-auto-migrate\n";
      }
      $no_automigrate = 1;
    }
    # -initial-dir <value>
    elsif ( ($arg eq '-initial-dir') or ($arg eq '--initial-dir') ) {
      print "Warning: Please use -initial-dir=<value> instead of $arg <value>\n";
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option $arg requires an argument");
      $force_initial_dir = shift @ARGV;
      print "Warning: Using $force_initial_dir as initial working directory\n";
    }
    # -initial-dir=<value>
    elsif ( $arg =~ /^-initial-dir=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -initial-dir= requires an argument");
      } else {
        $force_initial_dir = $argument_value;
      }
    }
    # -o <value>
    elsif ( ($arg eq '-o') ) {
      # Absorb -o argument, and don't pass it down to Clang
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option $arg requires a file argument.");
      $output_file = shift @ARGV;
      $output_file_arg = $output_file;
    }
    # -hash <value>
    elsif ( ($arg eq '-hash') or ($arg eq '--hash') ) {
      print "Warning: Please use -hash=<value> instead of $arg <value>\n";
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option $arg requires an argument");
      $program_hash = shift @ARGV;
    }
    # -hash=<value>
    elsif ( $arg =~ /^-hash=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -hash= requires an argument");
      } else {
        $program_hash = $argument_value;
      }
    }    
    # -clang-arg <option>
    elsif ( ($arg eq '-clang-arg') or ($arg eq '--clang-arg') ) {
      print "Warning: Please use -clang-arg=<options> instead of $arg <option>\n";
      $#ARGV >= 0 or mydie("Option $arg requires an argument");
      # Just push onto @args!
      push @args, shift @ARGV;
    }
    # -clang-arg=option1,option2,option3,...
    elsif ( $arg =~ /^-clang-arg=(.*)$/ ) {
      my @input_options = split(/,/, $1);
      $#input_options >= 0 or mydie("Option -clang-arg= requires at least one argument");
      push @args, @input_options;
    }
    # -opt-arg <option>
    elsif ( ($arg eq '-opt-arg') or ($arg eq '--opt-arg') ) {
      print "Warning: Please use -opt-arg=<options> instead of $arg <option>\n";
      $#ARGV >= 0 or mydie("Option $arg requires an argument");
      $opt_arg_after .= " ".(shift @ARGV);
    }
    # -opt-arg=option1,option2,option3,...
    elsif ( $arg =~ /^-opt-arg=(.*)$/ ) {
      my @input_options = split(/,/, $1);
      $#input_options >= 0 or mydie("Option -opt-arg= requires at least one argument");
      while (@input_options) {
        my $input_option = shift @input_options;
        $opt_arg_after .= " ".$input_option;
      }
    }
    # -one-pass <value>
    elsif ( ($arg eq '-one-pass') or ($arg eq '--one-pass') ) {
      print "Warning: Please use -one-pass=<value> instead of $arg <value>\n";
      $#ARGV >= 0 or mydie("Option $arg requires an argument");
      $dft_opt_passes = " ".(shift @ARGV);
      $opt_only = 1;
    }
    # -one-pass=<value>
    elsif ( $arg =~ /^-one-pass=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -one-pass= requires an argument");
      } else {
        $dft_opt_passes = " ".$argument_value;
        $opt_only = 1;
      }
    }  
    # -llc-arg <option>
    elsif ( ($arg eq '-llc-arg') or ($arg eq '--llc-arg') ) {
      print "Warning: Please use -llc-arg=<options> instead of $arg <option>\n";
      $#ARGV >= 0 or mydie("Option $arg requires an argument");
      $llc_arg_after .= " ".(shift @ARGV);
    }
    # -llc-arg=option1,option2,option3,...
    elsif ( $arg =~ /^-llc-arg=(.*)$/ ) {
      my @input_options = split(/,/, $1);
      $#input_options >= 0 or mydie("Option -llc-arg= requires at least one argument");
      while (@input_options) {
        my $input_option = shift @input_options;
        $llc_arg_after .= " ".$input_option;
      }
    }
    # -short-names
    elsif ( ($arg eq '-short-names') or ($arg eq '--short-names') ) {
      if ($arg eq '--short-names') {
        print "Warning: Please use -short-names instead of --short-names\n";
      }
      $llc_arg_after .= " --set-dspba-feature=maxFilenamePrefixLength,integer,8,maxFilenameSuffixLength,integer,8";
    }
    # -optllc-arg <option>
    elsif ( ($arg eq '-optllc-arg') or ($arg eq '--optllc-arg') ) {
      print "Warning: Please use -optllc-arg=<options> instead of $arg <option>\n";
      $#ARGV >= 0 or mydie("Option $arg requires an argument");
      my $optllc_arg = (shift @ARGV);
      $opt_arg_after .= " ".$optllc_arg;
      $llc_arg_after .= " ".$optllc_arg;
    }
    # -optllc-arg=option1,option2,option3,...
    elsif ( $arg =~ /^-optllc-arg=(.*)$/ ) {
      my @input_options = split(/,/, $1);
      $#input_options >= 0 or mydie("Option -optllc-arg= requires at least one argument");
      while (@input_options) {
        my $input_option = shift @input_options;
        $opt_arg_after .= " ".$input_option;
        $llc_arg_after .= " ".$input_option;
      }
    }
    # -sysinteg-arg <option>
    elsif ( ($arg eq '-sysinteg-arg') or ($arg eq '--sysinteg-arg') ) {
      print "Warning: Please use -sysinteg-arg=<options> instead of $arg <option>\n";
      $#ARGV >= 0 or mydie("Option $arg requires an argument");
      $sysinteg_arg_after .= " ".(shift @ARGV);
    }
    # -sysinteg-arg=option1,option2,option3,...
    elsif ( $arg =~ /^-sysinteg-arg=(.*)$/ ) {
      my @input_options = split(/,/, $1);
      $#input_options >= 0 or mydie("Option -sysinteg-arg= requires at least one argument");
      while (@input_options) {
        my $input_option = shift @input_options;
        $sysinteg_arg_after .= " ".$input_option;
      }
    }
    # -max-mem-percent-with-replication <value>
    elsif ( ($arg eq '-max-mem-percent-with-replication') or ($arg eq '--max-mem-percent-with-replication') ) {
      print "Warning: Please use -max-mem-percent-with-replication=<value> instead of $arg <value>\n";
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option $arg requires an argument");
      $max_mem_percent_with_replication = (shift @ARGV);
    }
    # -max-mem-percent-with-replication=<value>
    elsif ( $arg =~ /^-max-mem-percent-with-replication=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -max-mem-percent-with-replication= requires an argument");
      } else {
        $max_mem_percent_with_replication = $argument_value;
      }
    }  
    # -c-acceleration
    elsif ( ($arg eq '-c-acceleration') or ($arg eq '--c-acceleration') ) {
      if ($arg eq '--c-acceleration') {
        print "Warning: Please use -c-acceleration instead of --c-acceleration\n";
      }
      $c_acceleration = 1;
    }
    # -parse-only
    elsif ( ($arg eq '-parse-only') or ($arg eq '--parse-only') ) {
      if ($arg eq '--parse-only') {
        print "Warning: Please use -parse-only instead of --parse-only\n";
      }
      $parse_only = 1;
      $atleastoneflag = 1;
    }
    # -opt-only
    elsif ( ($arg eq '-opt-only') or ($arg eq '--opt-only') ) {
      if ($arg eq '--opt-only') {
        print "Warning: Please use -opt-only instead of --opt-only\n";
      }
      $opt_only = 1;
      $atleastoneflag = 1;
    }
    # -v-only
    elsif ( ($arg eq '-v-only') or ($arg eq '--v-only') ) {
      if ($arg eq '--v-only') {
        print "Warning: Please use -v-only instead of --v-only\n";
      }
      $verilog_gen_only = 1;
      $atleastoneflag = 1;
    }
    # -ip-only
    elsif ( ($arg eq '-ip-only') or ($arg eq '--ip-only') ) {
      if ($arg eq '--ip-only') {
        print "Warning: Please use -ip-only instead of --ip-only\n";
      }
      $ip_gen_only = 1;
      $atleastoneflag = 1;
    }
    # -dump-csr
    elsif ( ($arg eq '-dump-csr') or ($arg eq '--dump-csr') ) {
      if ($arg eq '--dump-csr') {
        print "Warning: Please use -dump-csr instead of --dump-csr\n";
      }
      $llc_arg_after .= ' -csr';
    }
    # -skip-qsys
    elsif ( ($arg eq '-skip-qsys') or ($arg eq '--skip-qsys') ) {
      if ($arg eq '--skip-qsys') {
        print "Warning: Please use -skip-qsys instead of --skip-qsys\n";
      }
      $skip_qsys = 1;
      $atleastoneflag = 1;
    }
    # -c
    elsif ( ($arg eq '-c') ) {
      $compile_step = 1;
      $atleastoneflag = 1;
    } 
    # -dis
    elsif ( ($arg eq '-dis') or ($arg eq '--dis') ) {
      if ($arg eq '--dis') {
        print "Warning: Please use -dis instead of --dis\n";
      }
      $disassemble = 1;
    }
    # -tidy
    elsif ( ($arg eq '-tidy') or ($arg eq '--tidy') ) {
      if ($arg eq '--tidy') {
        print "Warning: Please use -tidy instead of --tidy\n";
      }
      $tidy = 1;
    }
    # -save-temps
    elsif ( ($arg eq '-save-temps') or ($arg eq '--save-temps') ) {
      if ($arg eq '--save-temps') {
        print "Warning: Please use -save-temps instead of --save-temps\n";
      }
      $save_temps = 1;
    }
    # -use-ip-library
    elsif ( ($arg eq '-use-ip-library') or ($arg eq '--use-ip-library') ) {
      if ($arg eq '--use-ip-library') {
        print "Warning: Please use -use-ip-library instead of --use-ip-library\n";
      }
      $use_ip_library = 1;
    }
    # -no-link-ip-library
    elsif ( ($arg eq '-no-link-ip-library') or ($arg eq '--no-link-ip-library') ) {
      if ($arg eq '--no-link-ip-library') {
        print "Warning: Please use -no-link-ip-library instead of --no-link-ip-library\n";
      }
      $use_ip_library = 0;
    }
    # -regtest_mode
    elsif ( ($arg eq '-regtest_mode') or ($arg eq '--regtest_mode') ) {
      if ($arg eq '--regtest_mode') {
        print "Warning: Please use -regtest_mode instead of --regtest_mode\n";
      }
      $regtest_mode = 1;
    }
    # -incremental
    elsif ( ($arg eq '-incremental') or ($arg eq '--incremental') ) {
      if ($arg eq '--incremental') {
        print "Warning: Please use -incremental instead of --incremental\n";
      }
      # assume target dir is the incremental dir
      $incremental = 1;
      $sysinteg_arg_after .= ' --incremental ';
    }
    # -input-dir <path>
    elsif ( ($arg eq '-input-dir') or ($arg eq '--input-dir') ) {
      print "Warning: Please use -input-dir=<path> instead of $arg <path>\n";
      # assume target dir is the incremental dir
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -input-dir requires a path to a previous compile directory");
      $input_dir = shift @ARGV;
      ( -e $input_dir && -d $input_dir ) or mydie("Option -input-dir must specify an existing directory");
    }
    # -input-dir=<path>
    elsif ( $arg =~ /^-input-dir=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -input-dir= requires a path to a previous compile directory");
      } else {
        $input_dir = $argument_value;
        ( -e $input_dir && -d $input_dir ) or mydie("Option -input-dir= must specify an existing directory");
      }
    } 
    # -incremental-save-partitions <filename>
    elsif ( ($arg eq '-incremental-save-partitions') or ($arg eq '--incremental-save-partitions') ) {
      print "Warning: Please use -incremental-save-partitions=<filename> instead of $arg <filename>\n";
      # assume target dir is the incremental dir
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -incremental-save-partitions requires a file containing partitions you wish to partition");
      $save_partition_file = shift @ARGV;
      $incremental = 1;
      ( -e $save_partition_file && -f $save_partition_file ) or mydie("Option -incremental-save-partitions must specify an existing file");
    }
    # -incremental-save-partitions=<filename>
    elsif ( $arg =~ /^-incremental-save-partitions=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option incremental-save-partitions= requires a file containing partitions you wish to partition");
      } else {
        $save_partition_file = $argument_value;
        $incremental = 1;
        ( -e $save_partition_file && -f $save_partition_file ) or mydie("Option -incremental-save-partitions= must specify an existing file");
      }
    }
    # -incremental-set-partitions <filename>
    elsif ( ($arg eq '-incremental-set-partitions') or ($arg eq '--incremental-set-partitions') ) {
      print "Warning: Please use -incremental-set-partitions=<filename> instead of $arg <filename>\n";
      # assume target dir is the incremental dir
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -incremental-set-partitions requires a file containing partitions you wish to partition");
      $set_partition_file = shift @ARGV;
      $incremental = 1;
      ( -e $set_partition_file && -f $set_partition_file ) or mydie("Option -incremental-set-partitions must specify an existing file");
    }
    # -incremental-set-partitions=<filename>
    elsif ( $arg =~ /^-incremental-set-partitions=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option incremental-set-partitions= requires a file containing partitions you wish to partition");
      } else {
        $set_partition_file = $argument_value;
        $incremental = 1;
        ( -e $set_partition_file && -f $set_partition_file ) or mydie("Option -incremental-set-partitions= must specify an existing file");
      }
    }
    # -floorplan <filename>
    elsif ( ($arg eq '-floorplan') or ($arg eq '--floorplan') ) {
      print "Warning: Please use -floorplan=<filename> instead of $arg <filename>\n";
      my $floorplan_file = acl::File::abs_path(shift @ARGV);
      ( -e $floorplan_file && -f $floorplan_file ) or mydie("Option --floorplan must specify an existing file");
      $sysinteg_arg_after .= ' --floorplan '.$floorplan_file;
    }
    # -floorplan=<filename>
    elsif ( $arg =~ /^-floorplan=(.*)$/ ) {
      my $floorplan_file = acl::File::abs_path($1);
      ( -e $floorplan_file && -f $floorplan_file ) or mydie("Option --floorplan must specify an existing file");
      $sysinteg_arg_after .= ' --floorplan '.$floorplan_file;
    }
    # -incremental-flow <flow-name>
    elsif ( ($arg eq '--incremental-flow') or ($arg eq '-incremental-flow') ) {
      print "Warning: Please use -incremental-flow=<flow-name> instead of $arg <flow-name>\n";
      my %incremental_flow_strats = (
        'retry-flat' => 1,
        'final-no-retry' => 1
      );
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Usage: -incremental-flow=<" . join("|", keys %incremental_flow_strats) . ">");
      my $retry_option = shift @ARGV;
      if (exists $incremental_flow_strats{$retry_option}) {
        $ENV{'INCREMENTAL_RETRY_STRATEGY'} = $retry_option;
      } else {
        die "$retry_option is not a valid -incremental-flow selection! Select from: <" . join("|", keys %incremental_flow_strats) . ">";
      }
    }
    # -incremental-flow=<flow-name>
    elsif ( $arg =~ /^-incremental-flow=(.*)$/ ) {
      my $retry_option = $1;
      my %incremental_flow_strats = (
        'retry-flat' => 1,
        'final-no-retry' => 1
      );
      $retry_option ne "" or mydie("Usage: -incremental-flow=<" . join("|", keys %incremental_flow_strats) . ">");
      if (exists $incremental_flow_strats{$retry_option}) {
        $ENV{'INCREMENTAL_RETRY_STRATEGY'} = $retry_option;
      } else {
        die "$retry_option is not a valid -incremental-flow selection! Select from: <" . join("|", keys %incremental_flow_strats) . ">";
      }
    }
    # -add-qsf "file1 file2 file3 ..."
    elsif ( ($arg =~ '-add-qsf') ) {
      print "Warning: Please use -add-qsf=<filenames> instead of $arg <filenames>\n";
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -add-qsf requires a space-separated list of files");
      my @qsf_files = split(/ /, (shift @ARGV));
      push @additional_qsf, @qsf_files;
    }
    # -add-qsf=file1,file2,file3,...
    elsif ( $arg =~ /^-add-qsf=(.*)$/ ) {
      my @input_files = split(/,/, $1);
      $#input_files >= 0 or mydie("Option -add-qsf= requires at least one argument");
      push @additional_qsf, @input_files;
    }
    # -fast-compile
    elsif ( ($arg eq '-fast-compile') or ($arg eq '--fast-compile') ) {

      if ($arg eq '--fast-compile') {
        print "Warning: Please use -fast-compile instead of --fast-compile\n";
      }

      my ($board_variant,) = acl::Env::board_hardware_default();
      my $acl_board_hw_path = get_acl_board_hw_path($board_variant);

      my $board_spec_xml = find_board_spec($acl_board_hw_path);
      my $non_override_bsp_flow = ":" . acl::Env::aocl_boardspec("$board_spec_xml", "defaultname");

      my $platform_type = acl::Env::aocl_boardspec("$board_spec_xml", "automigrate_type" . $non_override_bsp_flow);
      ($platform_type !~ /error/) or mydie("BSP compile-flow $non_override_bsp_flow not found\n");

      if ($platform_type =~ /^a10/) {
        $fast_compile_on = 1;
        $ENV{'AOCL_FAST_COMPILE'} = 1;
        print "$prog: Adding Quartus fast-compile settings.\nWarning: Circuit performance will be significantly degraded.\n";
      } else {
        mydie("Fast compile is not supported on your device family.\n");
      }
    }
    # -soft-region
    elsif ( ($arg eq '-soft-region') ) {
      $soft_region_on = 1;
    }
    # -fmax <value>
    elsif ( ($arg eq '-fmax') or ($arg eq '--fmax') ) {
      print "Warning: Please use -fmax=<value> instead of $arg <value>\n";
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -fmax requires an argument");
      $opt_arg_after .= ' -scheduler-fmax=';
      $llc_arg_after .= ' -scheduler-fmax=';
      my $fmax_constraint = (shift @ARGV);
      $opt_arg_after .= $fmax_constraint;
      $llc_arg_after .= $fmax_constraint;
    }
    # -fmax=<value>
    elsif ( $arg =~ /^-fmax=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -fmax= requires an argument");
      } else {
        $opt_arg_after .= " -scheduler-fmax=$argument_value";
        $llc_arg_after .= " -scheduler-fmax=$argument_value";
      }
    }  
    # -seed <value>
    elsif ( ($arg eq '-seed') or ($arg eq '--seed') ) {
      print "Warning: Please use -seed=<value> instead of $arg <value>\n";
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -seed requires an argument");
      $fit_seed = (shift @ARGV);
    }
    # -seed=<value>
    elsif ( $arg =~ /^-seed=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -seed= requires an argument");
      } else {
        $fit_seed = $argument_value;
      }
    }  
    # -no-lms
    elsif ( ($arg eq '-no-lms') or ($arg eq '--no-lms') ) {
      if ($arg eq '--no-lms') {
        print "Warning: Please use -no-lms instead of --no-lms\n";
      }
      $opt_arg_after .= " ".$lmem_disable_split_flag;
    }
    # -fp-relaxed
    # temporary fix to match broke documentation
    elsif ( ($arg eq '-fp-relaxed') or ($arg eq '--fp-relaxed') ) {
      if ($arg eq '--fp-relaxed') {
        print "Warning: Please use -fp-relaxed instead of --fp-relaxed\n";
      }
      $opt_arg_after .= " -fp-relaxed=true";
    }
    # -Os
    # enable sharing flow
    elsif ( ($arg eq '-Os') ) {
       $opt_arg_after .= ' -opt-area=true';
       $llc_arg_after .= ' -opt-area=true';
    }
    # -fpc
    # temporary fix to match broke documentation
    elsif ( ($arg eq '-fpc') or ($arg eq '--fpc') ) {
      if ($arg eq '--fpc') {
        print "Warning: Please use -fpc instead of --fpc\n";
      }
      $opt_arg_after .= " -fpc=true";
    }
    # -const-cache-bytes <value>
    elsif ( ($arg eq '-const-cache-bytes') or ($arg eq '--const-cache-bytes') ) {
      print "Warning: Please use -const-cache-bytes=<value> instead of $arg <value>\n";
      $sysinteg_arg_after .= ' --cic-const-cache-bytes';
      $opt_arg_after .= ' --cic-const-cache-bytes=';
      $llc_arg_after .= ' --cic-const-cache-bytes=';
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -const-cache-bytes requires an argument");
      my $const_cache_size = (shift @ARGV);
      my $actual_const_cache_size = 16384;
      # Allow for positive Real Numbers Only
      if (!($const_cache_size =~ /^\d+(?:\.\d+)?$/)) {
        mydie("Invalid argument for option --const-cache-bytes,<N> must be a positive real number.");      
      }
      while ($actual_const_cache_size < $const_cache_size ) {
        $actual_const_cache_size = $actual_const_cache_size * 2;
      }
      $sysinteg_arg_after .= " ".$actual_const_cache_size;
      $opt_arg_after .= $actual_const_cache_size;
      $llc_arg_after .= $actual_const_cache_size;
    }
    # -const-cache-bytes=<value>
    elsif ( $arg =~ /^-const-cache-bytes=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -const-cache-bytes= requires an argument");
      } else {
        my $const_cache_size = $argument_value;
        my $actual_const_cache_size = 16384;
        while ($actual_const_cache_size < $const_cache_size ) {
          $actual_const_cache_size = $actual_const_cache_size * 2;
        }
        $sysinteg_arg_after .= " --cic-const-cache-bytes $actual_const_cache_size";
        $opt_arg_after .= " --cic-const-cache-bytes=$actual_const_cache_size";
        $llc_arg_after .= " --cic-const-cache-bytes=$actual_const_cache_size";
      }
    }   
    # -board <value>
    elsif ( ($arg eq '-board') or ($arg eq '--board') ) {
      print "Warning: Please use -board=<value> instead of $arg <value>\n";
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -board requires an argument");
      ($board_variant) = (shift @ARGV);
      $user_defined_board = 1;
    }
    # -board=<value>
    elsif ( $arg =~ /^-board=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -board= requires an argument");
      } else {
        $board_variant = $argument_value;
        $user_defined_board = 1;
      }
    } 
    # -board-package=<path>
    elsif ( $arg =~ /^-board-package=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -board-package= requires an argument");
      } else {
        $bsp_variant = $argument_value;
      }
    } 
    # -efi-spec <value>
    elsif ( ($arg eq '-efi-spec') or ($arg eq '--efi-spec') ) {
      print "Warning: Please use -efi-spec=<value> instead of $arg <value>\n";
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -efi-spec requires a path/filename");
      !defined $efispec_file or mydie("Too many EFI Spec files provided\n");
      $efispec_file = (shift @ARGV);
    }
    # -efi-spec=<value>
    elsif ( $arg =~ /^-efi-spec=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -efi-spec= requires an argument");
      } else {
        !defined $efispec_file or mydie("Too many EFI Spec files provided\n");
        $efispec_file = $argument_value;
      }
    } 
    # -I <name>
    # -Iinc syntax falls through to default below (even if first letter of inc id ' '
    elsif ( ($arg eq '-I') ) { 
        ($#ARGV >= 0 && $ARGV[0] !~ m/^-./) or mydie("Option $arg requires a name argument.");
        push  @args, $arg.(shift @ARGV);
    }
    # -L <path>
    elsif ($arg eq '-L') {
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -L requires a directory name");
      push (@lib_paths, (shift @ARGV));
    }
    # -L<path>
    elsif ($arg =~ m!^-L(\S+)!) {
      push (@lib_paths, $1);
    }
    # -l <libname>
    elsif ($arg eq '-l') {
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -l requires a path/filename");
      push (@lib_files, (shift @ARGV));
    }
    # -library-debug
    elsif ( ($arg eq '-library-debug') or ($arg eq '--library-debug') ) {
      if ($arg eq '--library-debug') {
        print "Warning: Please use -library-debug instead of --library-debug\n";
      }
      $opt_arg_after .= ' -debug-only=libmanager';
      $library_debug = 1;
    }
    # -shared
    elsif ( ($arg eq '-shared') or ($arg eq '--shared') ) {
      if ($arg eq '--shared') {
        print "Warning: Please use -shared instead of --shared\n";
      }
      $created_shared_aoco = 1;
      $compile_step = 1; # '-shared' implies '-c'
      $atleastoneflag = 1;
      # Enabling -g causes problems when compiling resulting
      # library for emulator (crash in 2nd clang invocation due
      # to debug info inconsistencies). Disabling for now.
      #push @args, '-g'; #  '-shared' implies '-g'
      
      # By default, when parsing OpenCL files, clang will mark every
      # non-kernel function as static. This option prevents this.
      push @args, '-dont-make-opencl-functions-static';
    }
    # -profile-config <file>
    elsif ( ($arg eq '-profile-config') or ($arg eq '--profile-config') ) {
      print "Warning: Please use -profile-config=<filename> instead of $arg <filename>\n";
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -profile-config requires a path/filename");
      !defined $profilerconf_file or mydie("Too many profiler config files provided\n");
      $profilerconf_file = (shift @ARGV);
    }
    # -profile-config=<file>
    elsif ( $arg =~ /^-profile-config=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -profile-config= requires a path/filename");
      } else {
        !defined $profilerconf_file or mydie("Too many profiler config files provided\n");
        $profilerconf_file = $argument_value;
      }
    } 
    # -bsp-flow <flow-name>
    elsif ( ($arg eq '-bsp-flow') or ($arg eq '--bsp-flow') ) {
      print "Warning: Please use -bsp-flow=<flow-name> instead of $arg <flow-name>\n";
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -bsp-flow requires a flow-name\n");
      !defined $bsp_flow_name or mydie("Too many bsp-flows defined.\n");
      $bsp_flow_name = (shift @ARGV);
      $sysinteg_arg_after .= " --bsp-flow $bsp_flow_name";
      $bsp_flow_name = ":".$bsp_flow_name;
    }
    # -bsp-flow=<flowname>
    elsif ( $arg =~ /^-bsp-flow=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -bsp-flow= requires a flow-name");
      } else {
        !defined $bsp_flow_name or mydie("Too many bsp-flows defined.\n");
        $bsp_flow_name = $argument_value;
        $sysinteg_arg_after .= " --bsp-flow $bsp_flow_name";
        $bsp_flow_name = ":".$bsp_flow_name;
      }
    } 
    # -vfabric
    elsif ( ($arg eq '-vfabric') or ($arg eq '--vfabric') ) {
      if ($arg eq '--vfabric') {
        print "Warning: Please use -vfabric instead of --vfabric\n";
      }
      $vfabric_flow = 1;
    }
    # -oldbe
    elsif ( ($arg eq '-oldbe') or ($arg eq '--oldbe') ) {
      if ($arg eq '--oldbe') {
        print "Warning: Please use -oldbe instead of --oldbe\n";
      }
      $griffin_flow = 0;
    }
    # -create-template
    elsif ( ($arg eq '-create-template') or ($arg eq '--create-template') ) {
      if ($arg eq '--create-template') {
        print "Warning: Please use -create-template instead of --create-template\n";
      }
      $generate_vfabric = 1;
    }
    # -reuse-existing-templates
    elsif ( ($arg eq '-reuse-existing-templates') or ($arg eq '--reuse-existing-templates') ) {
      if ($arg eq '--reuse-existing-templates') {
        print "Warning: Please use -reuse-existing-templates instead of --reuse-existing-templates\n";
      }
      $reuse_vfabrics = 1;
    }
    # -template-seed <value>
    elsif ( ($arg eq '-template-seed') or ($arg eq '--template-seed') ) {
      print "Warning: Please use -template-seed=<value> instead of $arg <value>\n";
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -template-seed requires an argument");
      $vfabric_seed = (shift @ARGV);
    }
    # -template-seed=<value>
    elsif ( $arg =~ /^-template-seed=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -template-seed= requires an argument");
      } else {
        $vfabric_seed = $argument_value;
      }
    } 
    # -template-library-path <value>
    elsif ( ($arg eq '-template-library-path') or ($arg eq '--template-library-path') ) {
      print "Warning: Please use -template-library-path=<value> instead of $arg <value>\n";
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -template-library-path requires an argument");
      $custom_vfab_lib_path = (shift @ARGV);
    }
    # -template-library-path=<value>
    elsif ( $arg =~ /^-template-library-path=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -template-library-path= requires an argument");
      } else {
        $custom_vfab_lib_path = $argument_value;
      }
    } 
    # -ggdb / -march=emulator
    elsif ($arg eq '-ggdb' || $arg eq '-march=emulator' ) {
      $emulator_flow = 1;
      if ($arg eq '-ggdb') {
        $dash_g = 1;
      }
    }
    # -soft-ip-c <function-name>
    elsif ( ($arg eq '-soft-ip-c') or ($arg eq '--soft-ip-c') ) {
      print "Warning: Please use -soft-ip-c=<function-name> instead of $arg <function-name>\n";
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -soft-ip-c requires a function name");
      $soft_ip_c_name = (shift @ARGV);
      $soft_ip_c_flow = 1;
      $verilog_gen_only = 1;
      $dotfiles = 1;
      print "Running soft IP C flow on function $soft_ip_c_name\n";
    }
    # -soft-ip-c=<function-name>
    elsif ( $arg =~ /^-soft-ip-c=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -soft-ip-c= requires a function name");
      } else {
        $soft_ip_c_name = $argument_value;
        $soft_ip_c_flow = 1;
        $verilog_gen_only = 1;
        $dotfiles = 1;
        print "Running soft IP C flow on function $soft_ip_c_name\n";
      }
    } 
    # -accel <function-name>
    elsif ( ($arg eq '-accel') or ($arg eq '--accel') ) {
      print "Warning: Please use -accel=<function-name> instead of $arg <function-name>\n";
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -accel requires a function name");
      $accel_name = (shift @ARGV);
      $accel_gen_flow = 1;
      $llc_arg_after .= ' -csr';
      $compile_step = 1;
      $atleastoneflag = 1;
      $sysinteg_arg_after .= ' --no-opencl-system';
    }
    # -accel=<function-name>
    elsif ( $arg =~ /^-accel=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -accel= requires a function name");
      } else {
        $accel_name = $argument_value;
        $accel_gen_flow = 1;
        $llc_arg_after .= ' -csr';
        $compile_step = 1;
        $atleastoneflag = 1;
        $sysinteg_arg_after .= ' --no-opencl-system';
      }
    } 
    # -device-spec <filename>
    elsif ( ($arg eq '-device-spec') or ($arg eq '--device-spec') ) {
      print "Warning: Please use -device-spec=<filename> instead of $arg <filename>\n";
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -device-spec requires a path/filename");
      $device_spec = (shift @ARGV);
    }
    # -device-spec=<filename>
    elsif ( $arg =~ /^-device-spec=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -device-spec= requires a path/filename");
      } else {
        $device_spec = $argument_value;
      }
    }
    # -dot
    elsif ( ($arg eq '-dot') or ($arg eq '--dot') ) {
      if ($arg eq '--dot') {
        print "Warning: Please use -dot instead of --dot\n";
      }
      $dotfiles = 1;
    }
    # -pipeline-viewer
    elsif ( ($arg eq '-pipeline-viewer') or ($arg eq '--pipeline-viewer') ) {
      $dotfiles = 1;
      $pipeline_viewer = 1;
    }
    # -time
    elsif ( ($arg eq '-time') or ($arg eq '--time') ) {
      if ($arg eq '--time') {
        print "Warning: Please use -time instead of --time\n";
      }
      if($#ARGV >= 0 && $ARGV[0] !~ m/^-./) {
        $time_log_filename = shift(@ARGV);
      }
      else {
        $time_log_filename = "-"; # Default to stdout.
      }
    }
    # -time=<file>
    elsif ( $arg =~ /^-time=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -time requires a filename");
      } else {
        $time_log_filename = $argument_value;
      }
    }
    # -time-passes
    elsif ( ($arg eq '-time-passes') or ($arg eq '--time-passes') ) {
      if ($arg eq '--time-passes') {
        print "Warning: Please use -time-passes instead of --time-passes\n";
      }
      $time_passes = 1;
      $opt_arg_after .= ' --time-passes';
      $llc_arg_after .= ' --time-passes';
      if(!$time_log_filename) {
        $time_log_filename = "-"; # Default to stdout.
      }
    }
    # -un
    # Temporary test flag to enable Unified Netlist flow.
    elsif ( ($arg eq '-un') or ($arg eq '--un') ) {
      if ($arg eq '--un') {
        print "Warning: Please use -un instead of --un\n";
      }
      $opt_arg_after .= ' --un-flow';
      $llc_arg_after .= ' --un-flow';
    }
    # -no-interleaving <name>
    elsif ( ($arg eq '-no-interleaving') or ($arg eq '--no-interleaving') ) {
      print "Warning: Please use -no-interleaving=<name> instead of $arg <name>\n";
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -no-interleaving requires a memory name or 'default'");
      if($ARGV[0] ne 'default' ) {
        $sysinteg_arg_after .= ' --no-interleaving '.(shift @ARGV);
      }
      else {
        #non-heterogeneous sw-dimm-partition behaviour
        #this will target the default memory
        shift(@ARGV);
        $sysinteg_arg_after .= ' --cic-global_no_interleave ';
      }
      $llc_arg_after .= ' -use-swdimm';
    }
    # -no-interleaving=<name>
    elsif ( $arg =~ /^-no-interleaving=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -no-interleaving requires a memory name or 'default'");
      } elsif ($argument_value eq 'default') {
        $sysinteg_arg_after .= ' --cic-global_no_interleave ';     
      } else {
        $sysinteg_arg_after .= ' --no-interleaving '.$argument_value;
      }
      $llc_arg_after .= ' -use-swdimm';
    }   
    # -global-tree
    elsif ( ($arg eq '-global-tree') or ($arg eq '--global-tree') ) {
      if ($arg eq '--global-tree') {
        print "Warning: Please use -global-tree instead of --global-tree\n";
      }
      $sysinteg_arg_after .= ' --global-tree';
      $llc_arg_after .= ' -global-tree';
    } 
    # -duplicate-ring
    elsif ( ($arg eq '-duplicate-ring') or ($arg eq '--duplicate-ring') ) {
      if ($arg eq '--duplicate-ring') {
        print "Warning: Please use -duplicate-ring instead of --duplicate-ring\n";
      }
      $sysinteg_arg_after .= ' --duplicate-ring';
    } 
    # -num-reorder <value>
    elsif ( ($arg eq '-num-reorder') or ($arg eq '--num-reorder') ) {
      print "Warning: Please use -num-reorder=<value> instead of $arg <value>\n";
      $sysinteg_arg_after .= ' --num-reorder '.(shift @ARGV);
    }
    # -num-reorder=<value>
    elsif ( $arg =~ /^-num-reorder=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -num-reorder= requires an argument");
      } else {
        $sysinteg_arg_after .= ' --num-reorder '.$argument_value;
      }
    }
    elsif ( process_meta_args ($arg, \@ARGV) ) { }
    # -input=kernel_1.cl,kernel_2.cl,kernel_3.cl,...
    elsif ( $arg =~ /^-input=(.*)$/ ) {
      my @input_files = split(/,/, $1);
    }
    elsif ( $arg =~ m/\.cl$|\.c$|\.aoco|\.xml/ ) {
      push @given_input_files, $arg;
    }
    elsif ( $arg =~ m/\.aoclib/ ) {
      mydie("Library file $arg specified without -l option");
    }
    # -dsploc <value>
    elsif ( ($arg eq '-dsploc') or ($arg eq '--dsploc') ) {
      print "Warning: Please use -dsploc=<value> instead of $arg <value>\n";
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -dsploc requires an argument");
      $dsploc = (shift @ARGV);
    }
    # -dsploc=<value>
    elsif ( $arg =~ /^-dsploc=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -dsploc= requires an argument");
      } else {
        $dsploc = $argument_value;
      }
    }
    # -ramloc <value>
    elsif ( ($arg eq '-ramloc') or ($arg eq '--ramloc') ) {
      print "Warning: Please use -ramloc=<value> instead of $arg <value>\n";
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -ramloc requires an argument");
      $ramloc = (shift @ARGV);
    }
    # -ramloc=<value>
    elsif ( $arg =~ /^-ramloc=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -ramloc= requires an argument");
      } else {
        $ramloc = $argument_value;
      }
    }
    # -O3
    elsif ($arg eq '-O3') {
      $emu_optimize_o3 = 1;
    }
    # -emulator-channel-depth-model <value>
    elsif ( ($arg eq '-emulator-channel-depth-model') or ($arg eq '--emulator-channel-depth-model') ) {
      print "Warning: Please use -emulator-channel-depth-model instead of $arg <value>\n";
      ($#ARGV >= 0 and $ARGV[0] !~ m/^-./) or mydie("Option -emulator-channel-depth-model requires an argument");
      $emu_ch_depth_model = (shift @ARGV);
    }
    # -emulator-channel-depth-model=<value>
    elsif ( $arg =~ /^-emulator-channel-depth-model=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        mydie("Option -emulator-channel-depth-model= requires an argument");
      } else {
        $emu_ch_depth_model = $argument_value;
      }
    }
    # -D__IHC_USE_DEPRECATED_NAMES
    elsif ($arg eq '-D__IHC_USE_DEPRECATED_NAMES') {
      print "$prog: Warning: Turning on use of deprecated names!\n";
      push @args, $arg;
    }
    # Unrecognized Option
    else {
      push @args, $arg;
    }
  }

  # Process $time_log_filename. If defined, then treat it as a file name 
  # (including "-", which is stdout).
  # Do this right after argument parsing, so that following code is able to log times.
  if ($time_log_filename) {
    my $fh;
    if ($time_log_filename ne "-") {
      # If this is an initial run, clobber time_log_filename, otherwise append to it.
      if (not $run_quartus) {
        open ($fh, '>', $time_log_filename) or mydie ("Couldn't open $time_log_filename for time output.");
      } else {
        open ($fh, '>>', $time_log_filename) or mydie ("Couldn't open $time_log_filename for time output.");
      }
    }
    else {
      # Use STDOUT.
      open ($fh, '>&', \*STDOUT) or mydie ("Couldn't open stdout for time output.");
    }

    # From this point forward, $time_log_fh holds the file handle!
    $time_log_fh = $fh;
  }

  # Don't add -g to user_opencl_args because -g is now enabled by default.
  # Instead add -g0 if the user explicitly disables debug info.
  push @user_opencl_args, @args;
  if (!$dash_g) {
    push @user_opencl_args, '-g0';
  }

  # Propagate -g to clang, opt, and llc
  if ($dash_g || $profile) {
    if ($emulator_flow && ($emulator_arch eq 'windows64')){
      print "$prog: Debug symbols are not supported in emulation mode on Windows, ignoring -g.\n" if $user_dash_g;
    } elsif ($created_shared_aoco) {
      print "$prog: Debug symbols are not supported for shared object files, ignoring -g.\n" if $user_dash_g;
    } else {
      push @args, '-g';
    }
    $opt_arg_after .= ' -dbg-info-enabled';
    $llc_arg_after.= ' -dbg-info-enabled';
  }

  # -board-package provided
  if (defined $bsp_variant) {
    $ENV{"AOCL_BOARD_PACKAGE_ROOT"} = $bsp_variant;
    # if no board variant was given by the --board option fall back to the default board
    if (!defined $board_variant) {
      ($board_variant) = acl::Env::board_hardware_default();
      $using_default_board = 1;
    # treat EmulatorDevice as undefined so we get a valid board
    } elsif ($board_variant eq $emulatorDevice) {
      ($board_variant) = acl::Env::board_hardware_default();
    } 
  # -board-package not provided
  } else {
    if (!defined $board_variant) {
      ($board_variant) = acl::Env::board_hardware_default();
      $using_default_board = 1;
    # treat EmulatorDevice as undefined so we get a valid board
    } elsif ($board_variant eq $emulatorDevice) {
      ($board_variant) = acl::Env::board_hardware_default();
    # Try to get the corresponding bsp
    } else {
      my @bsp_candidates = ();
      populate_boards();
      foreach my $b (keys %board_boarddir_map) {
        my ($board_name, $bsp_path) = split(';',$b);
        if ($board_variant eq $board_name) {
          push @bsp_candidates, $bsp_path; 
        }
      }
      if ($#bsp_candidates == 0) {
        $ENV{"AOCL_BOARD_PACKAGE_ROOT"} = shift @bsp_candidates;
      } elsif ($#bsp_candidates > 0) {
        print "Error: $board_variant exists in multiple board packages:\n";
        foreach my $bsp_path (@bsp_candidates) {
          print "$bsp_path\n";
        }
        print "Please use -board-package=<bsp-path> to specify board package\n";
        exit(1);
      # backward compatibility
      # if the specified board is not in the list, try with AOCL_BOARD_PACKAGE_ROOT
      } else {
        $ENV{'AOCL_BOARD_PACKAGE_ROOT'} = $old_board_package_root; 
      }  
    }
  }

  @user_clang_args = @args;

  if ($regtest_mode){
      $save_temps = 1;
      $report = 1;
      $sysinteg_arg_after .= ' --regtest_mode ';
      # temporary app data directory
      $tmp_dir = ( $^O =~ m/MSWin/ ? "S:/tools/aclboardpkg/.platform/BAK_cache": "/tools/aclboardpkg/.platform/BAK_cache" );
      if(!$regtest_bak_cache) {
        push @blocked_migrations, 'post_skipbak';
      }
      $llc_arg_after .= " -dump-hld-area-debug-files";
  }

  if ($dotfiles) {
    $opt_arg_after .= ' --dump-dot ';
    $llc_arg_after .= ' --dump-dot ';
    $sysinteg_arg_after .= ' --dump-dot ';
  }

  $orig_dir = acl::File::abs_path('.');
  $force_initial_dir = acl::File::abs_path( $force_initial_dir || '.' );

  # get the absolute path for the EFI Spec file
  if(defined $efispec_file) {
      chdir $force_initial_dir or mydie("Can't change into dir $force_initial_dir: $!\n");
      -f $efispec_file or mydie("Invalid EFI Spec file $efispec_file: $!");
      $absolute_efispec_file = acl::File::abs_path($efispec_file);
      -f $absolute_efispec_file or mydie("Internal error. Can't determine absolute path for $efispec_file");
      chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");
  }
  
  # Resolve library args to absolute paths
  if($#lib_files > -1) {
     if ($verbose or $library_debug) { print "Resolving library filenames to full paths\n"; }
     foreach my $libpath (@lib_paths, ".") {
        if (not defined $libpath) { next; }
        if ($verbose or $library_debug) { print "  lib_path = $libpath\n"; }
        
        chdir $libpath or next;
          for (my $i=0; $i <= $#lib_files; $i++) {
             my $libfile = $lib_files[$i];
             if (not defined $libfile) { next; }
             if ($verbose or $library_debug) { print "    lib_file = $libfile\n"; }
             if (-f $libfile) {
               my $abs_libfile = acl::File::abs_path($libfile);
               if ($verbose or $library_debug) { print "Resolved $libfile to $abs_libfile\n"; }
               push (@resolved_lib_files, $abs_libfile);
               # Remove $libfile from @lib_files
               splice (@lib_files, $i, 1);
               $i--;
             }
          }
        chdir $orig_dir;
     }
     
     # Make sure resolved all lib files
     if ($#lib_files > -1) {
        mydie ("Cannot find the following specified library files: " . join (' ', @lib_files));
     }
  }

  # User may have specified multiple input files, either directly or via libraries.
  # Merge them into one to present to compiler.
  my ($input_file, $base) = process_input_file_arguments();

  my $suffix = $base;
  $suffix =~ s/.*\.//;
  $base=~ s/\.$suffix//;
  my $ori_base = $input_file;
  $ori_base =~ s/\.$suffix//;
  $base =~ s/[^a-z0-9_]/_/ig;

  if ( $suffix =~ m/^cl$|^c$/ ) {
    $srcfile = $input_file;
    $objfile = $base.".aoco";
    $x_file = $base.".aocx";
    $dirbase = $base;
  } elsif ( $suffix =~ m/^aoco$/ ) {
    $run_quartus = 1;
    $srcfile = undef;
    $objfile = $ori_base.".aoco";
    $x_file = $base.".aocx";
    $dirbase = $ori_base;
  } elsif ( $suffix =~ m/^xml$/ ) {
    # xml suffix is for packaging RTL components into aoco files, to be
    # included into libraries later.
    # The flow is the same as for "aoc -shared -c" for OpenCL components
    # but currently handled by "aocl-libedit" executable
    $hdl_comp_pkg_flow = 1;
    $run_quartus = 0;
    $compile_step = 1;
    $srcfile = $input_file;
    $objfile = $base.".aoco";
    $x_file = $base.".aocx";
    $dirbase = $base;
  } else {
    mydie("No recognized input file format on the command line");
  }    

  if ( $output_file ) {
    my $outsuffix = $output_file;
    $outsuffix =~ s/.*\.//;
    # Did not find a suffix. Use default for option.
    if ($outsuffix ne "aocx" && $outsuffix ne "aoco") {
      if ($compile_step == 0) {
        $outsuffix = "aocx";
      } else {
        $outsuffix = "aoco";
      }
      $output_file .= "."  . $outsuffix;
    }
    my $outbase = $output_file;
    $outbase =~ s/\.$outsuffix//;
    if ($outsuffix eq "aoco") {
      ($run_quartus == 0 && $compile_step != 0) or mydie("Option -o argument cannot end in .aoco when used to name final output"); 
      $objfile = $outbase.".".$outsuffix;
      $dirbase = $outbase;
      $x_file = undef;
    } elsif ($outsuffix eq "aocx") {
      $compile_step == 0 or mydie("Option -o argument cannot end in .aocx when used with -c");  
      # There are two scenarios where aocx can be used:
      # 1. Input is a AOCO
      # 2. Input is a source file
      #
      # If the input is a AOCO, then $objfile and $dirbase is already set correctly.
      # If the input is a source file, set $objfile and $dirbase based on the AOCX name.
      if ($suffix ne "aoco") {
        $objfile = $outbase . ".aoco";
        $dirbase = $outbase;
      }
      $x_file = $output_file;
    } elsif ($compile_step == 0) {
      mydie("Option -o argument must be a filename ending in .aocx when used to name final output");
    } else {
      mydie("Option -o argument must be a filename ending in .aoco when used with -c");
    }
    $output_file = acl::File::abs_path( $output_file );
  }

  # For incremental compile to preserve partitions correctly, project name ($base) must be the same as
  # the previous compile. The $base name will be used in the hpath, so it is required to preserve the
  # previous partitions.
  # The $dirbase, .aoco, and .aocx file names will not be changed.
  if ($incremental) {
    my $prev_info = "";
    if ($input_dir && -e "$input_dir/reports/lib/json/info.json") {
      $prev_info = "$input_dir/reports/lib/json/info.json";
    } elsif ($dirbase && -e "$dirbase/reports/lib/json/info.json") {
      $prev_info = "$dirbase/reports/lib/json/info.json";
    }
    $base = acl::Incremental::get_previous_project_name($prev_info) if $prev_info;
  }

  $objfile = acl::File::abs_path( $objfile );
  $x_file = acl::File::abs_path( $x_file );

  if ($srcfile){ # not necesaarily set for "aoc file.aoco" 
    chdir $force_initial_dir or mydie("Can't change into dir $force_initial_dir: $!\n");
    -f $srcfile or mydie("Invalid kernel file $srcfile: $!");
    $absolute_srcfile = acl::File::abs_path($srcfile);
    -f $absolute_srcfile or mydie("Internal error. Can't determine absolute path for $srcfile");
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");
  }

  # get the absolute path for the Profiler Config file
  if(defined $profilerconf_file) {
      chdir $force_initial_dir or mydie("Can't change into dir $force_initial_dir: $!\n");
      -f $profilerconf_file or mydie("Invalid profiler config file $profilerconf_file: $!");
      $absolute_profilerconf_file = acl::File::abs_path($profilerconf_file);
      -f $absolute_profilerconf_file or mydie("Internal error. Can't determine absolute path for $profilerconf_file");
      chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");
  }
  
  # Output file must be defined for this flow
  if ($hdl_comp_pkg_flow) {
    defined $output_file or mydie("Output file must be specified with -o for HDL component packaging step.\n");
  }
  if ($created_shared_aoco and $emulator_flow) {
    mydie("-shared is not compatible with emulator flow.");
  }

  # Can't do multiple flows at the same time
  if ($soft_ip_c_flow + $compile_step + $run_quartus >1) {
      mydie("Cannot have more than one of -c, --soft-ip-c --hw on the command line,\n cannot combine -c with *.aoco either\n");
  }

  # Griffin exclusion until we add further support
  # Some of these (like emulator) should probably be relaxed, even today
  if($griffin_flow == 1 && $vfabric_flow == 1){
    mydie("Backend not compatible with virtual fabric target");
  }
  if($griffin_flow == 1 && $soft_ip_c_flow == 1){
    mydie("Backend not compatible with soft-ip flow");
  }
  if($griffin_flow == 1 && $accel_gen_flow == 1){
    mydie("Backend not compatible with C acceleration flow");
  }

  # Check that this a valid board directory by checking for a board_spec.xml 
  # file in the board directory.
  if (not $run_quartus) {
    my $board_xml = get_acl_board_hw_path($board_variant)."/board_spec.xml";
    if (!-f $board_xml) {
      print "Board '$board_variant' not found.\n";
      my $board_path = acl::Board_env::get_board_path();
      print "Searched in the board package at: \n  $board_path\n";
      list_boards();
      print "If you are using a 3rd party board, please ensure:\n";
      print "  1) The board package is installed (contact your 3rd party vendor)\n";
      print "  2) You have used -board-package=<bsp-path> to specify the path to\n";
      print "     your board package installation\n";
      mydie("No board_spec.xml found for board '$board_variant' (Searched for: $board_xml).");
    }
    if( !$bsp_flow_name ) {
      # if the boardspec xml version is before 17.0, then use the default
      # flow for that board, which is the first and only flow
      if( "$ENV{'ACL_DEFAULT_FLOW'}" ne '' && ::acl::Env::aocl_boardspec( "$board_xml", "version" ) >= 17.0 ) {
        $bsp_flow_name = "$ENV{'ACL_DEFAULT_FLOW'}";
      } else {
        $bsp_flow_name = ::acl::Env::aocl_boardspec("$board_xml", "defaultname");
      }
      $sysinteg_arg_after .= " --bsp-flow $bsp_flow_name";
      $bsp_flow_name = ":".$bsp_flow_name;
    }
  }

  if ($new_sim_mode) {
    # We need vsim to be in the path to compile the verilog.
    query_vsim_version();
  }

  $work_dir = acl::File::abs_path("$dirbase");

  my %quartus_info = check_env($board_variant,$bsp_flow_name);
  if ($regtest_mode) {
    $tmp_dir .= "/$quartus_info{site}";
  }
  $ENV{'AOCL_TMP_DIR'} = "$tmp_dir" if ($ENV{'AOCL_TMP_DIR'} eq '');
  print "$prog: If necessary for the compile, your BAK files will be cached here: $ENV{'AOCL_TMP_DIR'}\n" if $verbose;

  if (not $run_quartus) {
    if(!$atleastoneflag && $verbose) {
      print "You are now compiling the full flow!!\n";
    }
    create_system ($base, $work_dir, $srcfile, $objfile, $board_variant, $using_default_board, $all_aoc_args, $bsp_flow_name, $input_dir);
  }
  if (not ($compile_step|| $parse_only || $opt_only || $verilog_gen_only)) {
    compile_design ($base, $work_dir, $objfile, $x_file, $board_variant, $all_aoc_args, $bsp_flow_name);
  }

  if ($time_log_fh) {
    close ($time_log_fh);
  }
}

sub query_vsim_version() {
    my $vsim_version_str = `vsim -version`;
    my $error_code = $?;

    if ($error_code != 0) {
        mydie("Error accessing ModelSim.  Please ensure you have a valid ModelSim installation on your path.\n" .
              "       Check your ModelSim installation with \"vsim -version\" \n"); 
    }

    $cosim_64bit = ($vsim_version_str =~ /64 vsim/);
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

# Generate tcl to build the simulator system.
# TODO: This should be implemented in System Integrator, as it knows what is going on for
# the device.
sub generate_msim_system_tcl($) {
  my $outfile = $_[0];
  open(BOARD_SPEC, "<board_spec.xml") or mydie "Couldn't open board_spec.xml for read! : $!\n";
  my $has_snoop = 0;
  while(<BOARD_SPEC>) {
    if (/interface name="board" port="acl_internal_snoop".*width="(\d*)"/) {
      $has_snoop = $1;
      last;
    }
  }
  close(BOARD_SPEC);

  # Generate the file.
  open(TCL, ">$outfile") or mydie "Couldn't open $outfile for write! : $!\n";
  print TCL <<"HERE";
package require -exact qsys 17.0

create_system msim_sim

# Basic clock and reset for the simulation
add_instance clock_reset hls_sim_clock_reset
set_instance_parameter_value clock_reset RESET_CYCLE_HOLD    120

# Main OpenCL controller for the Kernel Interface and Memory Divider
add_instance aoc_main aoc_sim_main_dpi_controller

# The Master BFM to control the Memory Bank Divider
add_instance bfm_master_mbd aoc_sim_mm_master_dpi_bfm
set_instance_parameter_value bfm_master_mbd AV_ADDRESS_W     31
set_instance_parameter_value bfm_master_mbd AV_SYMBOL_W      8
set_instance_parameter_value bfm_master_mbd AV_NUMSYMBOLS    4
set_instance_parameter_value bfm_master_mbd USE_BURSTCOUNT   0
set_instance_parameter_value bfm_master_mbd USE_READ_DATA_VALID 1
set_instance_parameter_value bfm_master_mbd READ_SIM_COMMANDS 0

# The Memory Bank Divider that handles multiple banks of memory.
add_instance mem_bank_divider acl_memory_bank_divider
set_instance_parameter_value mem_bank_divider NUM_BANKS 1
set_instance_parameter_value mem_bank_divider DATA_WIDTH 512

# The Kernel Interface that controls the OpenCL kernels
add_instance kernel_interface kernel_interface

# The Master BFM to control the Kernel Interface (will poll host process)
add_instance bfm_master_ki aoc_sim_mm_master_dpi_bfm
set_instance_parameter_value bfm_master_ki AV_ADDRESS_W    14
set_instance_parameter_value bfm_master_ki AV_SYMBOL_W      8
set_instance_parameter_value bfm_master_ki AV_NUMSYMBOLS    4
set_instance_parameter_value bfm_master_ki USE_BURSTCOUNT   0
set_instance_parameter_value bfm_master_ki USE_READ_DATA_VALID 1
set_instance_parameter_value bfm_master_ki READ_SIM_COMMANDS 1

# The generated OpenCL kernels
add_instance kernel_system kernel_system

# The Slave BFM that holds the simulated memory
add_instance mm_slave_bfm aoc_sim_mm_slave_dpi_bfm
set_instance_parameter_value mm_slave_bfm AV_ADDRESS_W     25
set_instance_parameter_value mm_slave_bfm AV_SYMBOL_W      8
set_instance_parameter_value mm_slave_bfm AV_NUMSYMBOLS    64
set_instance_parameter_value mm_slave_bfm USE_WAIT_REQUEST  1
set_instance_parameter_value mm_slave_bfm USE_READ_DATA_VALID   1
set_instance_parameter_value mm_slave_bfm USE_BURSTCOUNT   1
set_instance_parameter_value mm_slave_bfm AV_BURSTCOUNT_W   5
# 256 comes from HLS version
set_instance_parameter_value mm_slave_bfm AV_MAX_PENDING_READS   256

#Setup connections

# Connect the AOC main controller
add_connection clock_reset.clock aoc_main.clock
add_connection clock_reset.clock2x aoc_main.clock2x
add_connection clock_reset.reset aoc_main.reset
add_connection aoc_main.reset_ctrl clock_reset.reset_ctrl

# Connect the OCL kernel
# Clock/reset
add_connection clock_reset.clock kernel_system.clock_reset
HERE
  print TCL "add_connection clock_reset.clock kernel_system.cc_snoop_clk\n" if $has_snoop;
  print TCL << 'HERE';
add_connection clock_reset.clock2x kernel_system.clock_reset2x
add_connection clock_reset.reset kernel_system.clock_reset_reset
add_connection kernel_interface.kernel_cra kernel_system.kernel_cra
add_connection kernel_interface.kernel_irq_from_kernel kernel_system.kernel_irq
auto_assign_irqs bfm_master_ki

# The BFM slave is connected to the kernel's mem0
add_connection kernel_system.kernel_mem0 mm_slave_bfm.s0

# Connect the kernel interface (KI)
add_connection clock_reset.clock kernel_interface.clk
add_connection clock_reset.clock kernel_interface.kernel_clk
add_connection clock_reset.reset kernel_interface.reset
add_connection clock_reset.reset kernel_interface.sw_reset_in
add_connection bfm_master_ki.m0 kernel_interface.ctrl
add_connection aoc_main.kernel_interrupt kernel_interface.kernel_irq_to_host

# Connect the memory bank divider
add_connection clock_reset.clock mem_bank_divider.clk
add_connection clock_reset.clock mem_bank_divider.kernel_clk
add_connection clock_reset.reset mem_bank_divider.reset
add_connection kernel_interface.kernel_reset mem_bank_divider.kernel_reset
# add_connection mem_bank_divider.acl_bsp_memorg_host kernel_interface.acl_bsp_memorg_host0x018
HERE
  print TCL "add_connection mem_bank_divider.acl_bsp_snoop kernel_system.cc_snoop\n" if $has_snoop;
  print TCL << 'HERE';
add_connection mem_bank_divider.bank1 mm_slave_bfm.s0

# Connect the KI BFM master
add_connection clock_reset.clock bfm_master_ki.clock
add_connection clock_reset.reset bfm_master_ki.reset
add_connection bfm_master_mbd.m0 mem_bank_divider.s

# Connect the MBD BFM master
add_connection clock_reset.clock bfm_master_mbd.clock
add_connection clock_reset.reset bfm_master_mbd.reset

# Connect the BFM slave
add_connection clock_reset.clock mm_slave_bfm.clock
add_connection kernel_interface.kernel_reset mm_slave_bfm.reset

# And save the whole thing
HERE
  print TCL "sync_sysinfo_parameters\n" if $is_pro_mode;
  print TCL "save_system msim_sim\n";
  close(TCL);
}

sub generate_simulation_scripts() {
    # vsim version
    my $vsim_version_string = `vsim -version`;
    $vsim_version_string =~ s/^\s+|\s+$//g;

    # Working directories
    my $simscriptdir = "msim_sim/sim";
    my $cosimlib = $cosim_64bit ? 'aoc_cosim_msim' : 'aoc_cosim_msim32';
    # Script filenames
    my $fname_compilescript = $simscriptdir.'/msim_compile.tcl';
    my $fname_runscript = $simscriptdir.'/msim_run.tcl';
    my $fname_msimsetup = $simscriptdir.'/mentor/msim_setup.tcl';
    my $fname_svlib = $ENV{'INTELFPGAOCLSDKROOT'} . (isLinuxOS() ? "/host/linux64/lib/lib${cosimlib}" : "/windows64/bin/${cosimlib}");
    my $fname_exe_com_script = isLinuxOS() ? 'compile.sh' : 'compile.cmd';

    # Modify the msim_setup script
    post_process_msim_file($fname_msimsetup, $simscriptdir);
    
    # Generate the modelsim compilation script
    my $COMPILE_SCRIPT_FILE;
    open(COMPILE_SCRIPT_FILE, ">", $fname_compilescript) or mydie "Couldn't open $fname_compilescript for write!\n";
    print COMPILE_SCRIPT_FILE "onerror {abort all; exit -code 1;}\n";
    print COMPILE_SCRIPT_FILE "set VSIM_VERSION_STR \"$vsim_version_string\"\n";
    print COMPILE_SCRIPT_FILE "set QSYS_SIMDIR $simscriptdir\n";
    print COMPILE_SCRIPT_FILE "source $fname_msimsetup\n";
    print COMPILE_SCRIPT_FILE "set ELAB_OPTIONS \"+nowarnTFMPC";
    if (isWindowsOS()) {
        print COMPILE_SCRIPT_FILE " -nodpiexports";
    }
    print COMPILE_SCRIPT_FILE ($sim_debug ? " -voptargs=+acc\"\n"
                                          : "\"\n");
    print COMPILE_SCRIPT_FILE "dev_com\n";
    print COMPILE_SCRIPT_FILE "com\n";
    # We don't want to compile now, as it may hard code absolute pathnames, and this won't
    # work well on the farm, as they will be missing when we unpack the results.
    # print COMPILE_SCRIPT_FILE "elab\n";
    print COMPILE_SCRIPT_FILE "exit -code 0\n";
    close(COMPILE_SCRIPT_FILE);

    # Generate the run script
    my $RUN_SCRIPT_FILE;
    open(RUN_SCRIPT_FILE, ">", $fname_runscript) or mydie "Couldn't open $fname_runscript for write!\n";
    print RUN_SCRIPT_FILE "onerror {abort all; puts stderr \"The simulation process encountered an error and has aborted.\"; exit -code 1;}\n";
    print RUN_SCRIPT_FILE "set VSIM_VERSION_STR \"$vsim_version_string\"\n";
    print RUN_SCRIPT_FILE "set QSYS_SIMDIR $simscriptdir\n";
    print RUN_SCRIPT_FILE "if {\$tcl_platform(platform) == \"windows\"} {\n";
    print RUN_SCRIPT_FILE "  set fname_svlib \"\$::env(INTELFPGAOCLSDKROOT)/windows64/bin/${cosimlib}\"\n";
    print RUN_SCRIPT_FILE "  set fname_svlib [string map { \"\\\\\" \"/\"} \$fname_svlib]\n";
    print RUN_SCRIPT_FILE "} else {\n";
    print RUN_SCRIPT_FILE "  set fname_svlib \"\$::env(INTELFPGAOCLSDKROOT)/host/linux64/lib/lib${cosimlib}\"\n";
    print RUN_SCRIPT_FILE "}\n";
    print RUN_SCRIPT_FILE "source $fname_msimsetup\n";
    print RUN_SCRIPT_FILE "# Suppress warnings from the std arithmetic libraries\n";
    print RUN_SCRIPT_FILE "set StdArithNoWarnings 1\n";
    print RUN_SCRIPT_FILE "set ELAB_OPTIONS \"+nowarnTFMPC -dpioutoftheblue 1 -sv_lib \$fname_svlib";
    if (isWindowsOS()) {
        print RUN_SCRIPT_FILE " -nodpiexports";
    }
    print RUN_SCRIPT_FILE ($sim_debug ? " -voptargs=+acc\"\n"
                                      : "\"\n");
    print RUN_SCRIPT_FILE "elab\n";
    print RUN_SCRIPT_FILE "onfinish {stop}\n";
    print RUN_SCRIPT_FILE "quietly set StdArithNoWarnings 1\n";
    if ($sim_debug) {
      print RUN_SCRIPT_FILE "set WLFFilename \$env(WLF_NAME)\n";
      my $depth = defined($sim_debug_depth) ? " -depth $sim_debug_depth" : "";
      print RUN_SCRIPT_FILE "log -r *$depth\n";
    }
    print RUN_SCRIPT_FILE "run -all\n";
    print RUN_SCRIPT_FILE "set failed [expr [coverage attribute -name TESTSTATUS -concise] > 1]\n";
    print RUN_SCRIPT_FILE "if {\${failed} != 0} { puts stderr \"The simulation process encountered an error and has been terminated.\"; }\n";
    print RUN_SCRIPT_FILE "exit -code \${failed}\n";
    close(RUN_SCRIPT_FILE);

    # Generate a script that we'll call to compile the design
    my $EXE_COM_FILE;
    open(EXE_COM_FILE, '>', "$simscriptdir/$fname_exe_com_script") or die "Could not open file '$simscriptdir/$fname_exe_com_script' $!";
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
    } else {
      mydie("Unsupported OS detected\n");
    }
    close(EXE_COM_FILE);
    if(isLinuxOS()) {
      system("chmod +x $simscriptdir/$fname_exe_com_script"); 
    }
}
main();
exit 0;
# vim: set ts=2 sw=2 expandtab
