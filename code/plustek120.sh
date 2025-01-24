#!/bin/bash
# plustek120.s Tool to facilitate scanning of 120 negatives on a Plustek 8100
# 

sane_dir="$HOME/opt/local_sane"
tmp_dir="scan_parts"
height_mm=40
offset_mm=8
res_dpi=3600
preview_height_mm=20
preview_res_dpi=600
preview_name="pre"
do_capture=true
do_merge=true
do_low_pass_filter=false
img_kernel="5x5:  
     0.25,-0.25,-1.00,-0.25, 0.25 
    -0.25, 0.25, 1.00, 0.25,-0.25 
    -1.00, 1.00, 4.00, 1.00,-1.00
    -0.25, 0.25, 1.00, 0.25,-0.25
     0.25,-0.25,-1.00,-0.25, 0.25
    "
img_kernel_scale=0.2

sane_args=("--mode" "Color" "--resolution" "$res_dpi" "-y" "$height_mm" "-t" "$offset_mm")
sane_preview_args=("--mode" "Color" "--resolution" "$preview_res_dpi" "-y" "$preview_height_mm" "-t" "$offset_mm" "-o" "$tmp_dir/$preview_name.tif")
sanecmd () { 
    LD_LIBRARY_PATH="$sane_dir/lib" "$sane_dir"/bin/scanimage "$@"
}

# Handle args
if [ $# -eq 0 ]
then
    fname="merge.tif"    
else
    fname="$1"
fi
if [[ $@ == *' -m' ]]
then
    # Skip capture, just merge
    do_capture=false
fi
if [ ! -d "$tmp_dir" ]
then
    mkdir "$tmp_dir"
fi

# Scan loop
scan_count=0;
while $do_capture
do
    read -rp "(r)efresh preview, (s)can or (m)erge? [R/s/m] " response
    if [ "$response" = "s" ]
    then
        scan_count=$((scan_count+1))
        sanecmd "${sane_args[@]}" -o "$tmp_dir/part_$scan_count.tif"
    elif [ "$response" = "m" ] 
    then
        echo "Merging."
        break
    else
        sanecmd "${sane_preview_args[@]}"
        continue
    fi
done

# Preprocess scans before merge
for f in "$tmp_dir"/part_*.tif
do
    [[ $f =~ "$tmp_dir"/part_([0-9]+)\.tif ]]
    idx="${BASH_REMATCH[1]}"
    echo Preprocessing "$tmp_dir"/part_"$idx".tif
    if [ -s "$tmp_dir"/part_"$idx".tif ]
    then 
        if [ $do_low_pass_filter ]
        then
            convert "$tmp_dir"/part_"$idx".tif \
                -define convolve:scale=$img_kernel_scale -morphology Convolve "$img_kernel" \
                "$tmp_dir"/ppart_"$idx".tif 
            convert "$tmp_dir"/ppart_"$idx".tif -set colorspace sRGB "$tmp_dir"/ppart_"$idx".tif 
        else
            convert "$tmp_dir"/part_"$idx".tif -set colorspace sRGB "$tmp_dir"/ppart_"$idx".tif 
        fi
        #echo Adding border to "$tmp_dir"/ppart_"$idx".tif
        #convert -bordercolor magenta -border 100 "$tmp_dir"/ppart_"$idx".tif "$tmp_dir"/ppart_"$idx".tif
    fi
done

# Merge
if [ $do_merge ]
then 
    pto_gen $tmp_dir/ppart_*.tif -p 0 -f 3 -o $tmp_dir/merge.pto # Generate PTO file
    cpfind -o $tmp_dir/merge.pto  --multirow $tmp_dir/merge.pto # Find control points with cpfind
    cpclean -o $tmp_dir/merge.pto $tmp_dir/merge.pto # Control point cleaning
    linefind -o $tmp_dir/merge.pto $tmp_dir/merge.pto # Find vertical lines
    autooptimiser -a -m -o $tmp_dir/merge.pto $tmp_dir/merge.pto 
    pano_modify -c -o $tmp_dir/merge.pto $tmp_dir/merge.pto # Center
    pano_modify --crop=AUTO -o $tmp_dir/merge.pto $tmp_dir/merge.pto # Crop 
    pano_modify --canvas=AUTO -o $tmp_dir/merge.pto $tmp_dir/merge.pto # Output canvas size 
    nona -o $tmp_dir/remapped_ -m TIFF_m $tmp_dir/merge.pto $tmp_dir/ppart_*.tif
    enblend -o "$fname" $tmp_dir/remapped_*.tif
fi
exit 
