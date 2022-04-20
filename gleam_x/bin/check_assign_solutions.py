#!/usr/bin/env python

"""Script to help identify which calibrate solution files are not appropriate to apply, and helps to 
identify ones close in time that are appropriate. 
"""

import os
import sys
import numpy as np
from calplots.aocal import fromfile
from argparse import ArgumentParser

try:
    from gleam_x.db import mysql_db as gxdb
except:
    print("Warning: unable to import the database connection")
    gxdb = None

THRESHOLD = (
    0.25  # acceptable level of flagged solutions before the file is considered ratty
)


def obtain_cen_chan(obsids, disable_db_check=False):
    """Retrieve the cenchan for a set of specified pointings. This will be done through the 
    meta-database, but should be expanded in the future to dial home to the mwa meta-data service

    Args:
        obsids (iterable): collection of obsids to check

    Keyword Args:
        disable_db_check (bool): Normal behaviour will raise an error if the GX database can not be contaced. If True this check is ignored (default: False)
    
    Returns:
        cenchans (numpy.ndarray): the cenchan of each obsid
    """
    cen_chan = np.array([1 for i in obsids])

    if gxdb is None:
        if disable_db_check:
            return cen_chan
        else:
            raise ValueError("GX Database configuration is not configured. ")

    try:
        con = gxdb.connect()

        obsids = [int(o) for o in obsids]

        cursor = con.cursor()

        # Need to wrangle the formatting so we can use the WHERE a IN b syntax
        cursor.execute(
            f"SELECT cenchan FROM observation WHERE obs_id IN ({', '.join(['%s' for _ in obsids])}) ",
            (*obsids,),
        )

        return np.squeeze(np.array([o[0] for o in cursor.fetchall()]))

    except:
        if disable_db_check:
            print("WARNING: Database lookup failed. Setting all cenchans to 1")
            return cen_chan
        else:
            raise ValueError("GX Database is not contactable. ")


def check_solutions(aofile, threshold=THRESHOLD, segments=None, *args, **kwargs):
    """Inspects the ao-calibrate solutions file to evaluate its reliability

    Args:
        aofile (str): aocal solutions file to inspect
    
    Keyword Args:
        threshold (float): The threshold, between 0 to 1, where too many solutions are flagged before the file becomes invalid (default: 0.25)

    Returns:
        bool: a valid of invalid aosolutions file
    """
    threshold = threshold / 100 if threshold > 1 else threshold
    if not os.path.exists(aofile):
        return False

    ao_results = fromfile(aofile)
    ao_flagged = np.sum(np.isnan(ao_results)) / np.prod(ao_results.shape)

    if ao_flagged > threshold:
        return False

    if segments is not None: 
        segments = int(segments)

        assert ao_results.shape[0] == 1, "Segment checks not implemented across multiple time steps"
        
        # shape is timestep, antenna, channel, pol
        no_chan = ao_results.shape[2]
        
        assert no_chan % segments == 0, f"{no_chan} channels is not evenly divisible by {segments} segments"
        stride = no_chan // segments
        
        for i in range(segments):
            chan_slice = slice(i*stride, (i+1)*stride)
            seg_ao_data = ao_results[:,:,chan_slice,:]
            seg_ao_flagged = np.sum(np.isnan(seg_ao_data)) / np.prod(seg_ao_data.shape)

            if seg_ao_flagged > threshold:
                return False
        
    return True


def report(obsids, cobsids, file=None, only_calids=False):
    """Report when an obsid has been associated with a new copied obsid solution file

    Args:
        obsid (iterable): Subject obsid with a missing solutions file
        cobsid (iterable): Obsid to copy solutions from
    
    Keyword Args:
        file (_io.TextIOWrapper): An open file handler to write to
    """
    for o, c in zip(obsids, cobsids):
        if only_calids:
            print(c, file=file)
        else:
            print(o, c, file=file)


def find_valid_solutions(
    obsids,
    dry_run=False,
    base_path=".",
    same_cen_chan=True,
    suffix="_local_gleam_model_solutions_initial_ref.bin",
    disable_db_check=False,
    *args,
    **kwargs,
):
    """Scans across a set of obsids to ensure a `calibrate` solutions file is found. If a obsids does not have this file, cidentify one close in time. 

    Directory structure is assumed to follow basic GLEAM-X pipeline:
        {obsid}/{obsid}{suffix}
    
    Minimal options are provide to configure this. 

    Args:
        obsids (numpy.ndarray): Array of obsids
    
    Keyword Args:
        dry_run (bool): Just present actions, do not carry them out (default: False)
        base_path (str): Prefix of path to search for ao-solutions (default: '.')
        same_cen_chan (bool): Force obsids to have the same central channel when considering candidate solutions (default: True)
        suffix (str): Suffix of the solution file, in GLEAM-X pipeline this is `{obsid}_{solution}` (default: '_local_gleam_model_solutions_initial_ref.bin')
        disable_db_check (bool): Normal behaviour will raise an error if the GX database can not be contaced. If True this check is ignored (default: False)

    Returns:
        calids (numpy.ndarray): Parrallel array with calibration solution obsid corresponding to the obsids specified in `obsids`
    """
    obsids = obsids.astype(np.int)
    calids = obsids.copy()

    sol_present = np.array(
        [
            check_solutions(f"{base_path}/{obsid}/{obsid}{suffix}", **kwargs)
            for obsid in obsids
        ]
    )

    if np.all(sol_present == False):
        print("No potenial calibration scans. base_path needs to be set?")
        sys.exit(1)

    if same_cen_chan:
        cen_chan = obtain_cen_chan(obsids, disable_db_check=disable_db_check)
    else:
        cen_chan = np.array([1 for obsid in obsids])

    chan_lookup = {k: k == cen_chan for k in np.unique(cen_chan)}

    for pos in np.argwhere(~sol_present):
        obsid = obsids[pos]

        obs_chan = cen_chan[pos][0]
        present = sol_present & chan_lookup[obs_chan]

        cobsid = obsids[present][np.argmin(np.abs(obsids[present] - obsid))]
        calids[pos] = cobsid

    return calids


if __name__ == "__main__":
    parser = ArgumentParser(
        description="Detects whether a calibration solution was successfully derived. Otherwise, will find an observation close in time and will copy solutions from that."
    )
    parser.add_argument(
        "-t",
        "--threshold",
        default=THRESHOLD,
        type=float,
        help=f"Threshold (between 0 to 1) of the acceptable number of NaN solutions before the entirety of solutions file considered void, defaults to {THRESHOLD}",
    )

    parser.add_argument(
        '-s',
        '--segments',
        type=int,
        default=None,
        help='Consider the flagging statistic checks on N number of sub-band segments. '
    )

    subparsers = parser.add_subparsers(dest="mode")

    check = subparsers.add_parser(
        "check", help="Check a ao-solutions file to see if it is valid"
    )
    check.add_argument(
        "aofile",
        type=str,
        nargs="+",
        help="Path to ao-solution file/s to check to see if it is valid",
    )

    assign = subparsers.add_parser(
        "assign",
        help="Assign a calibration ao-solutions file to a collection of obsids. Presents a report in stdout of obsid and corresponding calibration scan",
    )
    assign.add_argument(
        "obsids",
        type=str,
        help="Path to text file with obsids to consider. Text file is new line delimited",
    )
    assign.add_argument(
        "-n",
        "--no-report",
        action="store_true",
        default=False,
        help="Presents report of obsids and corresponding calibration obsid closest in time",
    )
    assign.add_argument(
        "-c",
        "--calids-out",
        default=None,
        type=str,
        help="Output text file to generate",
    )
    assign.add_argument(
        '--only-calids',
        default=False,
        action='store_true',
        help='When writing the output file, only write the calids column.'
    )
    assign.add_argument(
        "-b",
        "--base-path",
        type=str,
        default=".",
        help="Prefix added to path while scanning for ao-solution files",
    )
    assign.add_argument(
        "-a",
        "--any-cen-chan",
        default=False,
        action="store_true",
        help="The default behvious will be to consider the cen_chan property when assigning calibration IDs. This disables that check and only considers time when determining optimal calibration ID. ",
    )
    assign.add_argument(
        "--disable-db-check",
        action='store_true',
        default=False,
        help="Normal behaviour will raise an error if the GX database is not accessible. If True, this behaviour will be ignored, and no cen-chan information will be used. "
    )

    args = parser.parse_args()

    if args.mode == "check":
        print("Checking Mode")
        if args.segments is not None:
            print(f"Applying nan threshold checks to {args.segments} sub-bands")
        
        for f in args.aofile:
            if check_solutions(f, threshold=args.threshold, segments=args.segments):
                print(f"{f} passed")
            else:
                print(f"{f} failed")
    elif args.mode == "assign":
        print("Assigning calibration")
        if args.segments is not None:
            print(f"Applying nan threshold checks to {args.segments} sub-bands")

        obsids = np.loadtxt(args.obsids, dtype=int)
        calids = find_valid_solutions(
            obsids,
            threshold=args.threshold,
            same_cen_chan=not args.any_cen_chan,
            base_path=args.base_path.rstrip("/"),
            disable_db_check=args.disable_db_check
        )

        if not args.no_report:
            report(obsids, calids)
        if args.calids_out is not None:
            with open(args.calids_out, "w") as outfile:
                report(obsids, calids, file=outfile, only_calids=args.only_calids)
    else:
        print("Invalid directive supplied. ")
        parser.print_help()

