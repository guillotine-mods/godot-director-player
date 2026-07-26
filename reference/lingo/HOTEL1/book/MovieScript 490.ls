on finishday daynum
  global globalday
  if daynum = 1 then
    f = "endday"
    repeat with i = 1 to the number of items in line 1 of field "Dprocess" of castLib "master"
      if item i of line 1 of field "Dprocess" of castLib "master" <> "done" then
        f = "notyet"
      end if
    end repeat
    if (item 1 of line 6 of field "Dprocess" of castLib "master" <> "done") and (item 2 of line 6 of field "Dprocess" of castLib "master" <> "done") then
      f = "notyet"
    end if
    if f = "endday" then
      go(1, the moviePath & "golddead.dxr")
    else
      bk2peoplefunk()
    end if
  else
    if daynum = 2 then
      f = "endday"
      repeat with i = 1 to the number of items in line 2 of field "Dprocess" of castLib "master"
        if item i of line 2 of field "Dprocess" of castLib "master" <> "done" then
          f = "notyet"
        end if
      end repeat
      z = 0
      repeat with i = 1 to the number of items in line 6 of field "Dprocess" of castLib "master"
        if item i of line 6 of field "Dprocess" of castLib "master" = "done" then
          z = z + 1
        end if
      end repeat
      if (f = "endday") and (z >= 5) then
        go(1, the moviePath & "mirolo.dxr")
      else
        bk2peoplefunk()
      end if
    else
      if daynum = 3 then
        f = "endday"
        repeat with i = 1 to the number of items in line 3 of field "Dprocess" of castLib "master"
          if item i of line 3 of field "Dprocess" of castLib "master" <> "done" then
            f = "notyet"
          end if
        end repeat
        z = 0
        repeat with i = 1 to the number of items in line 6 of field "Dprocess" of castLib "master"
          if item i of line 6 of field "Dprocess" of castLib "master" = "done" then
            z = z + 1
          end if
        end repeat
        t = 0
        repeat with i = 1 to the number of lines in field "plane" of castLib "master"
          if line i of field "plane" of castLib "master" = "empty" then
            t = t + 1
          end if
        end repeat
        if (f = "endday") and (z >= 9) and (t = 0) then
          go(1, the moviePath & "endmovi1.dxr")
          repeat with s = 103 to 110
            sprite(s).visible = 0
          end repeat
        else
          bk2peoplefunk()
        end if
      end if
    end if
  end if
end

on bk2peoplefunk
end
