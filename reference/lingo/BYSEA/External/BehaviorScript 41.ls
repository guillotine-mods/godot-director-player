on exitFrame
  sticktimes = 0
  firetimes = 0
  prplortimes = 0
  ednatimes = 0
  repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
    case line i of field "objectsfield" of castLib "master" of
      "stick":
        sticktimes = sticktimes + 1
      "fire":
        firetimes = firetimes + 1
      "prplor":
        prplortimes = prplortimes + 1
      "edna":
        ednatimes = ednatimes + 1
    end case
  end repeat
  if sticktimes > 0 then
    repeat with f = 1 to sticktimes
      repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
        if line i of field "objectsfield" of castLib "master" = "stick" then
          objplc = i
        end if
      end repeat
      repeat with i = objplc + 1 to the number of lines in field "objectsfield" of castLib "master"
        put line i of field "objectsfield" of castLib "master" into line i - 1 of field "objectsfield" of castLib "master"
      end repeat
      put "empty" into line the number of lines in field "objectsfield" of castLib "master" of field "objectsfield" of castLib "master"
    end repeat
  end if
  if firetimes > 0 then
    repeat with f = 1 to firetimes
      repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
        if line i of field "objectsfield" of castLib "master" = "fire" then
          objplc = i
        end if
      end repeat
      repeat with i = objplc + 1 to the number of lines in field "objectsfield" of castLib "master"
        put line i of field "objectsfield" of castLib "master" into line i - 1 of field "objectsfield" of castLib "master"
      end repeat
      put "empty" into line the number of lines in field "objectsfield" of castLib "master" of field "objectsfield" of castLib "master"
    end repeat
  end if
  if prplortimes > 1 then
    repeat with f = 1 to prplortimes - 1
      repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
        if line i of field "objectsfield" of castLib "master" = "prplor" then
          objplc = i
        end if
      end repeat
      repeat with i = objplc + 1 to the number of lines in field "objectsfield" of castLib "master"
        put line i of field "objectsfield" of castLib "master" into line i - 1 of field "objectsfield" of castLib "master"
      end repeat
      put "empty" into line the number of lines in field "objectsfield" of castLib "master" of field "objectsfield" of castLib "master"
    end repeat
  end if
  if ednatimes > 0 then
    repeat with f = 1 to ednatimes
      repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
        if line i of field "objectsfield" of castLib "master" = "edna" then
          objplc = i
        end if
      end repeat
      repeat with i = objplc + 1 to the number of lines in field "objectsfield" of castLib "master"
        put line i of field "objectsfield" of castLib "master" into line i - 1 of field "objectsfield" of castLib "master"
      end repeat
      put "empty" into line the number of lines in field "objectsfield" of castLib "master" of field "objectsfield" of castLib "master"
    end repeat
  end if
  displayobject()
end
