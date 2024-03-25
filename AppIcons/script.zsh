

mkdir -p Resized
mkdir -p Rounded

for img in "$@"; do
  filename=$(basename $img)
  new_filepath="./Rounded/$filename"
  width=$(identify -format "%w" $img)
  height=$(identify -format "%h" $img)
  radius=$(echo "$width * 0.15" | bc)
  radius=$(printf "%.0f" $radius)
  convert -size ${width}x${height} xc:none -fill white -draw "roundRectangle 0,0,$width,$height,$radius,$radius" mask.png
  convert $img mask.png -compose DstIn -composite $new_filepath
  rm mask.png
done

for img in "$@"; do
  base_name=$(basename $img .png)
  mkdir -p "Resized/${base_name}.appiconset"
  jsonFile="Contents.json"
  cp $jsonFile "Resized/${base_name}.appiconset"

  jq -c '.images.[]' $jsonFile | while read -r item; do
    filename=$(echo "$item" | jq -r '.filename')
    echo "Detecting $filename"

    if [[ "$filename" == null ]]; then
      continue
    fi

    if [[ $filename == rounded* ]]; then
      rounded=true
      size=${filename#rounded_}
    else
      rounded=false
      size=${filename}
    fi

    size=${size%.png}

    
    outFile="Resized/${base_name}.appiconset/$filename"
    if [[ "$rounded" == "true" ]]; then
      echo "Converting Rounded/$base_name.png to $outFile"
      convert "Rounded/$base_name.png" -resize ${size}x${size} $outFile
    else
      echo "Converting $img to $outFile"
      convert "$img" -resize ${size}x${size} $outFile
    fi
  done
done
