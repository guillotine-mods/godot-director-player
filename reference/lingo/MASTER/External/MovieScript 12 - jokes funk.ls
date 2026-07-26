on jokesfunk
end

on runjokes y
  global soundspath, globalday
  setmoviepath("jokes")
  set the volume of sound 2 to 50
  window("jokes.dxr").windowType = 2
  tell window("jokes.dxr")
    www(y)
  end tell
  tell window("jokes.dxr")
    set the centerStage to 1
  end tell
  if globalday = 1 then
    open(window("jokes.dxr"))
    sound playFile 1, soundspath & "joke" & globalday & y & "a.aif"
    tell window("jokes.dxr")
      play frame "aspeak"
    end tell
  else
    if (globalday = 2) and ((y = 1) or (y = 5)) then
      open(window("jokes.dxr"))
      sound playFile 1, soundspath & "joke" & globalday & y & "a.aif"
      tell window("jokes.dxr")
        play frame "itamar"
      end tell
    else
      if (globalday = 3) and (y = 1) then
        open(window("jokes.dxr"))
        sound playFile 1, soundspath & "joke" & globalday & y & "a.aif"
        tell window("jokes.dxr")
          play frame "joke31"
        end tell
      else
        if (globalday = 3) and (y = 5) then
          open(window("jokes.dxr"))
          sound playFile 1, soundspath & "joke" & globalday & y & "a.aif"
          tell window("jokes.dxr")
            play frame "aspeak"
          end tell
        else
          if (globalday = 4) and (y = 1) then
            open(window("jokes.dxr"))
            sound playFile 1, soundspath & "joke" & globalday & y & "a.aif"
            tell window("jokes.dxr")
              play frame "itamar"
            end tell
          else
            if (globalday = 5) and (y = 2) then
              open(window("jokes.dxr"))
              sound playFile 1, soundspath & "pip1.aif"
              tell window("jokes.dxr")
                play frame "joke52"
              end tell
            else
              if (globalday = 5) and (y = 4) then
                open(window("jokes.dxr"))
                sound playFile 1, soundspath & "joke" & globalday & y & "a.aif"
                tell window("jokes.dxr")
                  play frame "joke54"
                end tell
              else
                open(window("jokes.dxr"))
                sound playFile 1, soundspath & "joke" & globalday & y & "a.aif"
                tell window("jokes.dxr")
                  play frame "youngstart"
                end tell
              end if
            end if
          end if
        end if
      end if
    end if
  end if
end

on cardsfunk
end

on runcards
  i = 1
  x = "not"
  repeat while (i < the number of items in field "afganifield") and (x = "not")
    if item i of field "afganifield" = "0" then
      put "1" into item i of field "afganifield"
      x = "yes"
      next repeat
    end if
    i = i + 1
  end repeat
end

on missionfunk
  global mission, globalday, nof
  if globalday = 2 then
    if (mission = 1) and (nof = "dl5") then
      sprite(39).visible = 1
      sprite(40).visible = 0
    else
      if (mission = 2) and (nof = "kitchen") then
        set the cursor of sprite 38 to [member("trgcur1").memberNum, member("trgcur2").memberNum]
      else
        if (mission = 3) or (mission = 4) then
          set the cursor of sprite 38 to [member("trgcur1").memberNum, member("trgcur2").memberNum]
          set the cursor of sprite 39 to [member("trgcur1").memberNum, member("trgcur2").memberNum]
        else
          if (mission = 5) and (nof = "dr1") then
            set the cursor of sprite 39 to [member("trgcur1").memberNum, member("trgcur2").memberNum]
          else
            sprite(39).visible = 0
            sprite(40).visible = 0
          end if
        end if
      end if
    end if
  else
    if (mission = 1) and (nof = "t3") then
      sprite(39).visible = 1
      sprite(40).visible = 0
    else
      if (mission = 2) and (nof = "engineroom") then
        set the cursor of sprite 39 to [member("trgcur1").memberNum, member("trgcur2").memberNum]
        sprite(38).visible = 0
      else
        if (mission = 3) or (mission = 4) then
          sprite(38).visible = 1
          set the cursor of sprite 38 to [member("trgcur1").memberNum, member("trgcur2").memberNum]
          set the cursor of sprite 39 to [member("trgcur1").memberNum, member("trgcur2").memberNum]
        else
          if (mission = 5) and (nof = "ur1") then
            set the cursor of sprite 39 to [member("trgcur1").memberNum, member("trgcur2").memberNum]
          else
            set the cursor of sprite 38 to [1, 1]
            sprite(39).visible = 0
            sprite(40).visible = 0
          end if
        end if
      end if
    end if
  end if
end
