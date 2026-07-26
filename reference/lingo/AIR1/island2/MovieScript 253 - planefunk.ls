on planefunk obj, objplc
  global soundspath, effectspath
  ppart = 0
  case obj of
    "igkey":
      ppart = 40
    "joystk":
      ppart = 41
    "fuel":
      ppart = 47
    "rotor":
      ppart = 48
    "shoes":
      ppart = 46
    "spring":
      ppart = 45
    "prplor":
      ppart = 49
    "engine":
      ppart = 43
    "chairs":
      ppart = 42
    "chair2":
      ppart = 44
  end case
  if ppart > 39 then
    sprite(ppart).visible = 1
    sound playFile 1, effectspath & "planpart.aif"
    x = value(the text of field "points" of castLib "master")
    x = x + 1
    if x < 10 then
      put "00" & x into field "points" of castLib "master"
    else
      put "0" & x into field "points" of castLib "master"
    end if
    yy = 1
    repeat with i = objplc + 1 to the number of lines in field "objectsfield" of castLib "master"
      put line i of field "objectsfield" of castLib "master" into line i - 1 of field "objectsfield" of castLib "master"
    end repeat
    put "empty" into line the number of lines in field "objectsfield" of castLib "master" of field "objectsfield" of castLib "master"
    ppart = ppart - 39
    put obj into line ppart of field "plane" of castLib "master"
    displayobject()
  end if
end
