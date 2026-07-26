on exitFrame
  global soundspath, globalnight
  if item 2 of globalnight = "0" then
    if not soundBusy(1) then
      sound playFile 1, soundspath & "steal1.aif"
    end if
  end if
end
