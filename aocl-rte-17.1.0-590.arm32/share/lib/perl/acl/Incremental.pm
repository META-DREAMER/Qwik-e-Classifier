=pod

=head1 NAME

acl::Incremental - Utility for incremental compile flows

=head1 COPYRIGHT

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


=cut

package acl::Incremental;
require Exporter;
use strict;
use acl::Common;
use acl::Env;
use acl::File;
use acl::Report qw(escape_string);

$acl::Incremental::warning = undef;

# Check if full incremental recompile is necessary
sub requires_full_recompile($$$$$$$$$$$) {
  $acl::Incremental::warning = undef;

  my ($input_dir, $base, $all_aoc_args, $board_name, $board_variant, $devicemodel, $devicefamily, $qversion, $program, $aclversion, $bnum) = @_;
  my ($quartus_version) = $qversion =~ /Version (.* Build \d*)/;
  my $acl_version       = "$aclversion Build $bnum";

  local $/ = undef;

  if (! -e "$input_dir/kernel_hdl") {
    $acl::Incremental::warning = "Warning: Cannot find kernel_hdl in previous project directory. Changes cannot be accurately detected. Performing full recompile.\n";
    return 1;
  } elsif (! -e "$input_dir/$base.bc.xml") {
    $acl::Incremental::warning = "Warning: Cannot find $base.bc.xml in previous project directory. Changes cannot be accurately detected. Performing full recompile.\n";
    return 1;
  } elsif (open(my $prev_info, "<$input_dir/reports/lib/json/info.json")) {
    my $info = <$prev_info>;
    close $prev_info;

    # Check project name
    my ($prev_proj_name) = $info =~ /Project Name.*?\[\"(.+?)\"\]/;
    if ($prev_proj_name ne escape_string($base)) {
      $acl::Incremental::warning = "Warning: Found different project $prev_proj_name in previous project directory. Performing full recompile.\n";
      return 1;
    }

    # Check target family, device, and board
    my ($prev_target_family, $prev_device, $prev_board_name) = $info =~ /Target Family, Device, Board.*?\[\"(.+?),\s+(.+?),\s+(.+?)\"\]/;
    if ($prev_target_family ne $devicefamily || $prev_device ne $devicemodel || $prev_board_name ne escape_string("$board_name:$board_variant")) {
      $acl::Incremental::warning = "Warning: Device differs from previous compile. Performing full recompile.\n";
      return 1;
    }

    # Check ACDS version
    my ($prev_ACDS_version) = $info =~ /Quartus Version.*?\[\"(.+?)\"\]/;
    if ($prev_ACDS_version ne $quartus_version) {
      $acl::Incremental::warning = "Warning: Quartus Version differs from previous compile. Performing full recompile.\n";
      return 1;
    }

    # Check AOC version
    my ($prev_AOC_version) = $info =~ /AOC Version.*?\[\"(.+?)\"\]/;
    if ($prev_AOC_version ne $acl_version) {
      $acl::Incremental::warning = "Warning: AOC Version differs from previous compile. Performing full recompile.\n";
      return 1;
    }

    # Check command line flags
    $program =~ s/#//g;
    my ($prev_command) = $info =~ /Command.*?\[\"$program\s+(.+?)\s*\"\]/;
    my @prev_args = split(/\s+/, $prev_command);
    my @curr_args = split(/\s+/, escape_string($all_aoc_args));
    if (compare_command_line_flags(\@prev_args, \@curr_args)) {
      $acl::Incremental::warning .= "Warning: Command line flags differ from previous compile. Performing full recompile.\n";
      return 1;
    }
  } else {
    $acl::Incremental::warning = "Warning: Cannot open reports $input_dir/reports/lib/json/info.json from previous incremental compile. " .
                                 "Change detection failed to perform command line flag check. Performing full recompile.\n";
    return 1;
  }
  return 0;
}

# Check if important command line options/flags match.
# This check only needs to identify diffs in command line options/flags
# that won't be detected by other stages of change detection.
sub compare_command_line_flags($$) {
  my ($prev_args, $curr_args) = @_;

  my $index = 0;
  ++$index until $index == scalar @$prev_args || $prev_args->[$index] eq "-c";
  if ($index != scalar @$prev_args) {
    $acl::Incremental::warning = "Warning: The previous compile was only run to the .aoco stage. ";
    $index = 0;
    ++$index until $index == scalar @$curr_args || $curr_args->[$index] eq "-c";
    if ($index != scalar @$curr_args) {
      $acl::Incremental::warning .= "If the compiler cannot find the previous partition files, it will recompile all partitions.\n";
    } else {
      $acl::Incremental::warning .= "Performing full recompile.\n";
      return 1;
    }
  }

  my @ref = @$prev_args;
  my @cmp = @$curr_args;
  my $swapped = 0;
  my @libs = ();
  # Flags are options that are either on or off and don't take an argument.
  my @flags_to_check = ('incremental');
  # Opt args are options with a mandatory argument.
  my @optargs_to_check = ('bsp-flow', 'sysinteg-arg');
  while (scalar @ref) {
    my $arg  = shift @ref;

    # Check for matching library in both sets
    if ($arg =~ m!^-l(\S+)! || $arg eq '-l') {

      if ($arg =~ m!^-l(\S+)!) {
        # There are some aoc options that start with -l which are
        # detected as library filenames using the above regex
        # so need to skip checking those options.
        my $full_opt = '-l' . $1;
        foreach my $exclude_name (@acl::Common::l_opts_exclude) {
          if ($full_opt =~ m!^$exclude_name!) {
            goto END;
          }
        }
      }

      my $length = scalar @cmp;
      $index = 0;

      my $ref_lib = ($arg =~ m!^-l(\S+)!) ? $1 : shift @ref;
      my $cmp_lib = "";
      while ($index < $length) {
        ++$index until $index == $length || $cmp[$index] eq "-l" || $cmp[$index] =~ m!^-l(\S+)!;
        last if ($index == $length);
        $cmp_lib   = $cmp[$index+1]             if ($cmp[$index] eq "-l");
        ($cmp_lib) = $cmp[$index] =~ /^-l(\S+)/ if ($cmp[$index] =~ m/^-l\S+/);
        last if ($cmp_lib eq $ref_lib);
        ++$index;

      }

      if ($ref_lib ne $cmp_lib) {
        # Need to include the library name or else the warning will just say
        # '-l' flag is missing from one of the compiles which is not specific
        # enough.
        $arg .= " $ref_lib" if ($arg eq '-l');
        _add_differing_flag_warning($arg, $swapped);
        return 1;
      }

      push @libs, $ref_lib;
      splice(@cmp, $index, ($cmp[$index] eq '-l') ? 2 : 1);

    } else {
      # Check if important command line flags match.
      foreach my $flag (@flags_to_check) {
        if ($arg eq "--$flag" || $arg eq "-$flag") {
          if (_compare_command_flag($flag, \@ref, \@cmp)) {
            _add_differing_flag_warning($arg, $swapped);
            return 1;
          }

          goto END;
        }
      }

      # Check if important option/argument pairs match.
      foreach my $optarg (@optargs_to_check) {
        if ($arg eq "--$optarg" || $arg eq "-$optarg" || $arg =~ m!^-$optarg=(\S+)!) {
          my $full_arg = $arg;
          if ($arg eq "--$optarg" || $arg eq "-$optarg") {
            # Need to report the option name and the argument value
            # in the command line flag warning. $arg only contains
            # the option name.
            $full_arg .= " $ref[0]";
          }

          if (_compare_command_opt_arg($optarg, $arg, \@ref, \@cmp)) {
            _add_differing_flag_warning($full_arg, $swapped);
            return 1;
          }

          goto END;
        }
      }
    }

    # May want to check for Optimization Controls in the future
    # For now, leave it to change detection to pick up the differences

    # If we've checked all command line flags in @prev_args against @curr_args,
    # swap the arrays and check any left over command line flags in @curr_args
    END:
    if (! scalar @ref) {
      @ref = @cmp;
      @cmp = ();
      $swapped = 1;
    }
  }

  if (scalar @libs) {
    $acl::Incremental::warning .= "Warning: The following libraries were used: " . join(', ', @libs) . ". Changes to libraries are not automatically detected in incremental compile.\n";
  }

  return 0;
}

# Generate initial incremental compile report
sub generate_initial_compile_report($) {
  $acl::Incremental::warning = undef;

  my ($json) = @_;

  my $fout         = "incremental.initial.rpt";
  my $report_title = " Initial Incremental Compile Report";

  # Read info from area.json file
  my $area = _read_data_from_file($json);
  $acl::Incremental::warning = "Warning: Cannot open area.json to create$report_title.\n" if ($area eq "");

  my @kernels = get_kernel_names($area);
  my @max_resources = $area =~ /\"max_resources\".*?\[(\d+), (\d+), (\d+), (\d+)\]/s;

  my @rows   = ();
  my %counts = ();
  push @rows, ["Partition Name", "ALUTs", "FFs", "RAMs", "DSPs"];

  my @gic_data = ($area ne "") ? _get_partition_area_data(["Global Interconnect", "", "Global interconnect"], $area, \@max_resources)    : ('-', '-', '-', '-');
  my @cc_data  = ($area ne "") ? _get_partition_area_data(["Constant Cache", "", "Constant cache interconnect"], $area, \@max_resources) : ('-', '-', '-', '-');
  push @rows, ["Global Interconnect", $gic_data[0], $gic_data[1], $gic_data[2], $gic_data[3]] if ($gic_data[0] ne '-');
  push @rows, ["Constant Cache"     , $cc_data[0],  $cc_data[1],  $cc_data[2],  $cc_data[3]]  if ($cc_data[0] ne '-');

  foreach my $kern (@kernels) {
    my @data = ($area ne "") ? _get_partition_area_data([$kern, "", $kern], $area, \@max_resources) : ('-', '-', '-', '-');
    push @rows, [$kern, $data[0], $data[1], $data[2], $data[3]] if ($data[0] ne '-');
  }

  _print_report($fout, $report_title, \@rows, \%counts);
}

# Generate report on change detection
sub generate_change_detection_report($$$) {
  $acl::Incremental::warning = undef;

  my ($prev_area_json, $curr_area_json, $partition_diff)  = @_;

  my $fout         = "incremental.change.rpt";
  my $report_title = " Change Detection Report";

  # Read info from area.json files
  my $parea_info = _read_data_from_file($prev_area_json);
  my $carea_info = _read_data_from_file($curr_area_json);
  if ($parea_info eq "" || $carea_info eq "") {
    $acl::Incremental::warning = "Warning: Cannot open area.json files to create$report_title.\n";
    return;
  }

  # Add area elements to report
  my @area_elements = ();

  # Add global IC and const cache
  # TODO: FB:489760 Once change detection and BBIC has been added for global IC,
  # properly populate the changed/preserved status.
  # Currently neither the global IC nor the constant cache IC are inside a partition.
  push @area_elements, ["Global Interconnect", "not partitioned", "Global interconnect"];
  push @area_elements, ["Constant Cache", "not partitioned", "Constant cache interconnect"];

  # Get partitions from change detection
  open(my $partitions, "<$partition_diff");
  if (!defined $partitions) {
    $acl::Incremental::warning = "Warning: Cannot open $partition_diff file to create$report_title.\n";
    return;
  }

  # Add partitions (this includes partition name, and the status of the partition)
  while(my $line = <$partitions>) {
    $line =~ s/\n//g;
    my @el = split(',', $line);
    push @area_elements, \@el;
  }
  close($partitions);

  # Collect area estimates
  my @rows = ();
  push @rows, ["Partition Name", "Status", "Previous ALUTs", "Current ALUTs", "Previous FFs", "Current FFs", "Previous RAMs", "Current RAMs", "Previous DSPs", "Current DSPs"];

  # Get max resources for device
  my @max_resources = (0, 0, 0, 0);

  # Track statistics for changes
  # total_ALUT is the the sum of all ALUTs used by
  # all the partitions in the current compile plus
  # the ALUTs used by the global and constant cache IC
  my %counts = (
    add_count      => 0,
    remove_count   => 0,
    preserve_count => 0,
    changed_count  => 0,
    total_ALUT     => 0,
    changed_ALUT   => 0
  );

  @max_resources = $carea_info =~ /\"max_resources\".*?\[(\d+), (\d+), (\d+), (\d+)\]/s;
  foreach my $pref (@area_elements) {
    my @el             = @{$pref};
    my $partition_name = $el[0];
    my $status         = $el[1];

    my @pdata = _get_partition_area_data($pref, $parea_info, \@max_resources);
    my @cdata = _get_partition_area_data($pref, $carea_info, \@max_resources);

    push @rows, [$partition_name, $status, $pdata[0], $cdata[0], $pdata[1], $cdata[1], $pdata[2], $cdata[2], $pdata[3], $cdata[3]] if ($pdata[0] ne '-' || $cdata[0] ne '-');

    ++$counts{add_count}      if ($status eq "added");
    ++$counts{remove_count}   if ($status eq "removed");
    ++$counts{preserve_count} if ($status eq "preserved");
    ++$counts{changed_count}  if ($status eq "changed");

    my ($ALUTs) = $cdata[0] =~ /(\d+.*?\d*?) \(/;
    $counts{total_ALUT} += $ALUTs;
    $counts{changed_ALUT} += $ALUTs if (($status eq "changed" || $status eq "added" || $status eq "not partitioned") && defined $ALUTs);
  }
  $acl::Incremental::warning .= "Warning: No changes detected. Performing incremental compile with all kernels preserved.\n"
                                unless ($counts{add_count} || $counts{remove_count} || $counts{changed_count});

  _print_report($fout, $report_title, \@rows, \%counts);
}

# Get names of the kernels in the design
sub get_kernel_names($) {
  my ($json) = @_;
  my @kernels = $json =~ /name\":\"(\S+)\"\n\s+, \"compute_units\":\d+\n\s+, \"type\":\"function.*?total_kernel_resources.*?\[/sg;
  return @kernels;
}

# Get the previous project name
sub get_previous_project_name($) {
  $acl::Incremental::warning = undef;
  my ($json) = @_;
  my $info = _read_data_from_file($json);
  my ($prj_name) = $info =~ /Project Name.*?\[\"(.+?)\"\]/;
  $acl::Incremental::warning = "Warning: Cannot find previous project name. Performing full recompile.\n" if ($prj_name eq "");
  return $prj_name;
}

# Get global parameters to overwrite
sub get_global_mem_parameters {
  my ($bc_xml) = @_;

  my $data = _read_data_from_file($bc_xml);
  my ($arbitration_latency, $kernel_side_mem_latency) = $data =~ /arbitration_latency=\"(\d+)\"\s+kernel_side_mem_latency=\"(\d+)\"/;

  return ($arbitration_latency, $kernel_side_mem_latency);
}

# Read in area.json file
sub _read_data_from_file($) {
  my ($json) = @_;
  local $/=undef;
  open(my $data, "<$json") or return "";
  my $content = <$data>;
  close($data);
  return $content;
}

# Get area estimates for a given partition
sub _get_partition_area_data($$$) {
  my ($el_ref, $area_info, $max_res) = @_;

  my @data = (0, 0, 0, 0);
  my @elements = @{$el_ref};
  my $exists = 0;

  # The change detection tool will print out <partition name>,<status>,<kernel in partition>,<next kernel in partition>,...
  # Add up the area of all kernels in the partition and report it as percent of max resources
  for (my $i = 2; $i < scalar @elements; ++$i) {
    my $elem = $elements[$i];
    my @temp_data;

    if ($elements[0] eq "Global Interconnect" || $elements[0] eq "Constant Cache") {
      @temp_data = $area_info =~ /name\":\"$elem\".*?\[(\d+.*?\d*?), (\d+.*?\d*?), (\d+.*?\d*?), (\d+.*?\d*?)\]/s;
    } else {
      # Function names could clash with some of the names of the other area rows, so this check must be more specific
      @temp_data = $area_info =~ /name\":\"$elem\"\n\s+, \"compute_units\":\d+\n\s+, \"type\":\"function.*?total_kernel_resources.*?\[(\d+.*?\d*?), (\d+.*?\d*?), (\d+.*?\d*?), (\d+.*?\d*?)\]/s;
    }

    if (defined @temp_data && scalar @temp_data == 4) {
      $data[0] += $temp_data[0];
      $data[1] += $temp_data[1];
      $data[2] += $temp_data[2];
      $data[3] += $temp_data[3];
      $exists = 1;
    }
  }

  @data = ($exists) ? _add_percentage_of_max_res(\@data, $max_res) : ('-', '-', '-', '-');
  return @data;
}

# Add percentage of device usage to absolute area estimates
sub _add_percentage_of_max_res($$) {
  my ($data, $max_resources) = @_;

  my @d  = @{$data};
  my @mr = @{$max_resources};
  for (my $i = 0; $i < scalar @d; ++$i) {
    next if (!$mr[$i]);
    $d[$i] = $d[$i] . " (" . _calculate_percentage($d[$i], $mr[$i]) . ")"; # round to 2 decimals
  }

  return @d;
}

# Calculate percentage of the rounded to one decimal point
sub _calculate_percentage($$) {
  my ($a, $b) = @_;
  my $fraction = ($b) ? ($a * 100 / $b) : 0; # $b should only be 0 when there's nothing in the design
  return substr( $fraction + 0.05, 0, length(int($fraction)) + 2 ) . "%";
}

# Given the file name, report title, rows in the report, and summary statistics, print the report
# This subroutine is used to print both the incremental.initial.rpt and the incremental.change.rpt
sub _print_report($$$$) {
  my ($output_file, $report_title, $rowref, $countref) = @_;
  my @rows     = @{$rowref};
  my %counts   = %{$countref};
  my $num_cols = scalar @{$rows[0]};

  # Calculate column width
  my @widths = (0) x $num_cols;
  foreach my $row (@rows) {
    my @arow = @{$row};
    for (my $i = 0; $i < scalar @arow; ++$i) {
      $widths[$i] = (length($arow[$i]) + 2 > $widths[$i]) ? length($arow[$i]) + 2 : $widths[$i];
    }
  }

  # Calculate full width
  my $full_width = 0;
  my $full_row = '+';
  foreach my $w (@widths) {
    $full_width += $w;
    $full_row   .= ( '-' x $w ) . '+';
  }
  $full_row .= "\n";

  # Print change detection report
  open(my $cd_rpt, ">$output_file");
  if (!defined $cd_rpt) {
    $acl::Incremental::warning .= "Warning: Cannot write to $output_file.\n";
    return;
  }

  print $cd_rpt '+' . ( '-' x ($full_width + $num_cols - 1) ) . "+\n";
  print $cd_rpt ';' . $report_title . (' ' x ($full_width - length($report_title) + $num_cols - 1)) . ";\n";

  # Print the given rows of the table
  print $cd_rpt $full_row;
  foreach my $row (@rows) {
    my @arow = @{$row};
    print $cd_rpt ';';
    for (my $i = 0; $i < scalar @widths; ++$i) {
      print $cd_rpt ' ' . $arow[$i] . (' ' x ($widths[$i] - length($arow[$i]) - 1)) . ';';
    }
    print $cd_rpt "\n";

    if ($arow[0] eq "Partition Name") {
      print $cd_rpt $full_row;
    }
  }
  print $cd_rpt $full_row;

  if ($output_file eq "incremental.change.rpt") {
    print $cd_rpt "\n" . $counts{preserve_count} . " partitions preserved, " .
                         $counts{changed_count}  . " partitions changed, "   .
                         $counts{add_count}      . " partitions added, "     .
                         $counts{remove_count}   . " partitions removed.\n";
    print $cd_rpt (($counts{total_ALUT}) ? _calculate_percentage($counts{changed_ALUT}, $counts{total_ALUT})
                                         : "-") . " of design changed.\n";
  }

  close($cd_rpt);
}

# Compare a command line flag between @$rref and @$rcmp.
# (eg. command line flags of the form '--flag' or any equivalent form)
# Return 0 if the flag in @$rref exists in @$rcmp and remove
# the matching flag from @$rcmp.
# Return 1 if the flag differs between @$rref and @$rcmp.
sub _compare_command_flag($$$) {
  my ($flag_name, $rref, $rcmp) = @_;

  my $cmp_length = scalar @$rcmp;
  my $cmp_index = 0;

  # There are currently 2 equivalent formats a flag can be specified.
  # 1) --flag
  # 2) -flag
  ++$cmp_index until $cmp_index == $cmp_length ||
                     $rcmp->[$cmp_index] eq "-$flag_name" ||
                     $rcmp->[$cmp_index] eq "--$flag_name";
  return 1 if ($cmp_index == $cmp_length);

  # Remove matching flag.
  splice(@$rcmp, $cmp_index, 1);
  return 0;
}

# Compare a command line option with an argument between @$rref and @$rcmp.
# (eg. compares command line options of the form '--option-name arg' or
# any equivalent form)
# Return 0 if the option/argument pair in @$rref exists in @$rcmp and remove
# the matching option/argument pair from @$rcmp.
# Return 1 if the option/argument pair differs between @$rref and @$rcmp.
sub _compare_command_opt_arg($$$$) {
  my ($opt_name, $opt, $rref, $rcmp) = @_;

  my $cmp_length = scalar @$rcmp;
  my $cmp_index = 0;

  my $ref_arg = ($opt =~ m!^-$opt_name=(\S+)!) ? $1 : shift @$rref;
  my $cmp_arg = undef;

  # Some options can be specified multiple times on the command line so we need to
  # compare all instances to find one with the same value.
  while ($cmp_index < $cmp_length) {
    # There are currently 3 equivalent formats an option/argument pair can be specified.
    # 1) --option-name arg
    # 2) -option-name arg
    # 3) -option-name=arg
    ++$cmp_index until $cmp_index == $cmp_length ||
                       $rcmp->[$cmp_index] eq "--$opt_name" ||
                       $rcmp->[$cmp_index] eq "-$opt_name" ||
                       $rcmp->[$cmp_index] =~ m!^-$opt_name=(\S+)!;

    # Did not find the same option argument pair in @$rcmp.
    last if ($cmp_index == $cmp_length);

    $cmp_arg = $rcmp->[$cmp_index+1] if ($rcmp->[$cmp_index] eq "--$opt_name" ||
                                         $rcmp->[$cmp_index] eq "-$opt_name");
    ($cmp_arg) = $rcmp->[$cmp_index] =~ /^-$opt_name=(\S+)/ if ($rcmp->[$cmp_index] =~ m/^-$opt_name=\S+/);

    # Found matching option/argument pair in @$rcmp.
    last if ($cmp_arg eq $ref_arg);
    ++$cmp_index;
  }

  return 1 if ($ref_arg ne $cmp_arg);

  # Remove the matching option/argument pair from @$rcmp.
  my $num_to_splice = $rcmp->[$cmp_index] eq "-$opt_name" || $rcmp->[$cmp_index] eq "--$opt_name" ? 2 : 1;
  splice(@$rcmp, $cmp_index, $num_to_splice);

  return 0;
}

# Add a warning specifying the flag that differs between the current and previous compile.
sub _add_differing_flag_warning($$) {
  my ($arg, $swapped) = @_;
  my $curr = $swapped ? "current" : "previous";
  my $prev = $swapped ? "previous" : "current";

  $acl::Incremental::warning .= "Warning: The $curr compile uses the command line " .
                                "flag $arg which is missing in the $prev compile.\n";
}

1;
