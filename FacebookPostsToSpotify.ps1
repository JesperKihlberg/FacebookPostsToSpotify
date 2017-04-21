
function FacebookPostsToSpotify([DateTime]$date, $cacheFilePath, $facebookToken, $facebookGroupId, $iftttApiKey, $youtubeApiKey) {
    $weeknb = get-date $date -uformat %V
    $year = $date.Year
    $day = $date.dayofweek
    $filename = "${cacheFilePath}songs_${year}_${weeknb}.xml"
    Write-Host $filename
    $songs = @{}
    if ([System.IO.File]::Exists( $filename)) {
        $songs = Import-CliXml $filename
    }
    $limit = 10
    $uri = "https://graph.facebook.com/${facebookGroupId}/feed?fields=link,message,is_published,created_time&limit=${limit}&access_token=${facebookToken}"
    $data = Invoke-RestMethod -Method Get -Uri $uri
    
#     $regexText = @'
# (?:[0-9A-Z-]+\.)?(?:youtu\.be\/|youtube(?:-nocookie)?\.com\S*?[^\w\s-])([\w-]{11})(?=[^\w-]|$)(?![?=&+%\w.-]*(?:['"][^<>]*>|<\/a>))[?=&+%\w.-]*
# '@
    $regexText = @'
(?:.+?)?(?:\/v\/|watch\/|\?v=|\&v=|youtu\.be\/|\/v=|^youtu\.be\/|watch\%3Fv\%3D)([a-zA-Z0-9_-]{11})+
'@
    $regex = [regex]$regexText
    $lastElementAtDate = 1
    while ($lastElementAtDate -eq 1) {
        foreach ($post in $data.data) {
            $created_time = get-date $post.created_time 
            if ($created_time.Date -eq $date.Date) {
                if (!$songs.ContainsKey($post.id)) {
                    $fbPost = @{ "id" = $post.id; 
                        "date" = $post.created_time; 
                        "postlink" = $post.link; 
                        "message" = $post.message;
                        "is_published" = $post.is_published;
                        "type" = "unknown"; 
                    }
                    $regexMatch = $regex.Match($post.link)
                    if ($regexMatch.Captures.groups.length -gt 0) {
                        Write-Host $regexMatch.Captures.groups[0] $regexMatch.Captures.groups[1] $regexMatch.Captures.groups[2] 
                        $youtubeId = $regexMatch.Captures.groups[1]
                        $fbPost["youtubeId"] = "" + ${youtubeId}
                        $fbPost["type"] = "youtube"
                        $title = GetYoutubeTitle $youtubeId $youtubeApiKey
                        $fbPost["youtubeTitle"] = ${title}
                        if ($title) {
                            $cleanupSongName = cleanupSongName($title)
                            $fbPost["cleanupSongName"] = ${cleanupSongName}
                            Start-Sleep -s 1
                            if ($cleanupSongName) {
                                Write-Host  $title
                                Write-Host  $cleanupSongName["artist"] "-" $cleanupSongName["name"]
                                addSongNameToSpotify $cleanupSongName["artist"] $cleanupSongName["name"] $iftttApiKey
                                $fbPost["addSongNameToSpotify"] = 1
                            }
                        }
                    }
                    $songs.Add($post.id, $fbPost)
                }
            }
            else {
                if ($created_time.Date -lt $date.Date) {
                    $lastElementAtDate = 0
                    break;
                }
            }
        }
        if ($lastElementAtDate -eq 1) {
            $uri = $data.paging.next
            $data = Invoke-RestMethod -Method Get -Uri $uri
        }
    }
    $songs | Export-CliXml $filename
    foreach ($song in $($songs.Values | Sort-Object -Property date)) {
        Write-Host  $song.id ";" $song.date ";" $song.postlink ";" $song.youtubeTitle ";" $song.cleanupSongName.artist ";" $song.cleanupSongName.name
    }
}
function GetYoutubeTitle($youtubeId, $youtubeApiKey) {
    $youtubeUri = "https://content.googleapis.com/youtube/v3/videos?id=${youtubeId}&part=snippet&key=${youtubeApiKey}"
    $data = Invoke-RestMethod -Method Get -Uri $youtubeUri
    return $data.items[0].snippet.title
}
function cleanupSongName($songname) {
    $cleanname = $songname.replace('[', '').replace(']', '').replace('/', ' ').replace('&', ' ');
    $songelems = $cleanname.split("-");
    $artist = $songelems[0]
    if ($songelems.Count -gt 1) {
        $name = $songelems[1]
        $mbUri = "http://musicbrainz.org/ws/2/recording/?query=artist:(${artist})%20AND%20${name}&limit=1&fmt=json"
    }
    else {
        $mbUri = "http://musicbrainz.org/ws/2/recording/?query=${artist}&limit=1&fmt=json"
    }
    $data = Invoke-RestMethod -Method Get -Uri $mbUri
    return @{"score" = $data.recordings.score; "name" = $data.recordings.title; "artist" = $data.recordings.'artist-credit'.artist.name; }
}
function addSongNameToSpotify($artist, $name, $iftttApiKey) {
    $spotUri = "https://maker.ifttt.com/trigger/add_song_to_spotify/with/key/${iftttApiKey}"
    $params = @{"value1" = "$artist";
        "value2" = "$name";
    }
    Invoke-WebRequest -Uri $spotUri -Method POST -Body $params
}
