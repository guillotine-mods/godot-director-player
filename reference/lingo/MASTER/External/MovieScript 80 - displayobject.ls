on displayobject
  i = 103
  repeat while i <= 110
    puppetSprite(i, 1)
    if line i - 102 of field "objectsfield" of castLib "master" <> "empty" then
      set the memberNum of sprite i to the number of member line i - 102 of field "objectsfield"
      set the moveableSprite of sprite i to 1
      set the cursor of sprite i to [the number of member "hand1", the number of member "hand2"]
    else
      set the memberNum of sprite i to the number of member "object0" of castLib "master"
    end if
    i = 1 + i
  end repeat
end
