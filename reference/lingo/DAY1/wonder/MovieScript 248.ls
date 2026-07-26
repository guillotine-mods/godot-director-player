on objecttalktime x
  global syz, egozv, egozh, usfultalking, usfulobject
  repeat with i = 18 to 21
    puppetSprite(i, 1)
  end repeat
  if member(the memberNum of sprite 30).name contains "stand" then
  else
    if member(the memberNum of sprite 30).name contains "right" then
      set the memberNum of sprite 30 to the number of member ("standright" & syz)
    else
      set the memberNum of sprite 30 to the number of member ("standleft" & syz)
    end if
    set the locV of sprite 30 to egozv
    set the locH of sprite 30 to egozh
  end if
  usfultalking = 1
  usfulobject = x
  if marker(0) = label("fieldgo") then
    go("fieldtalk")
  else
    if marker(0) = label("tennisgo") then
      go("tennistalk")
    else
      if marker(0) = label("edge1go") then
        go("edge1talk")
      else
        if marker(0) = label("verandago") then
          go("verandatalk")
        else
          if marker(0) = label("dwarfsgo") then
            if sprite the clickOn intersects 36 or sprite the clickOn intersects 37 then
              go("dwarfs2talk")
            else
              go("dwarfs1talk")
            end if
          else
            if marker(0) = label("exitforest3go") then
              go("exitforest3talk")
            else
            end if
          end if
        end if
      end if
    end if
  end if
end

on talkproc init, fieldname, lastmark
  global usfultalking, usfulline, usfulobject, soundspath, objtlkpath, egozv, egozh, syz
  if usfultalking = 1 then
    r = "not"
    i = 1
    repeat while (i < (the number of lines in field fieldname of castLib "master" + 1)) and (r = "not")
      if item 1 of line i of field fieldname = usfulobject then
        r = i
      end if
      i = i + 1
    end repeat
    if r <> "not" then
      usfulline = r
      egozh = the locH of sprite 30
      egozv = the locV of sprite 30
      sound playFile 1, objtlkpath & usfulobject & init & usfultalking & ".aif"
      usfultalking = usfultalking + 1
    end if
  else
    if (the number of items in line usfulline of field fieldname of castLib "master" - 1) >= usfultalking then
      sound playFile 1, objtlkpath & usfulobject & init & usfultalking & ".aif"
      usfultalking = usfultalking + 1
    else
      repeat with i = 18 to 21
        puppetSprite(i, 0)
      end repeat
      if member(the memberNum of sprite 30).name contains "right" then
        set the memberNum of sprite 30 to the number of member ("standright" & syz)
      else
        set the memberNum of sprite 30 to the number of member ("standleft" & syz)
      end if
      set the locV of sprite 30 to egozv
      set the locH of sprite 30 to egozh
      go(lastmark)
    end if
  end if
end
