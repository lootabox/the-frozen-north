const int BASE_LOCK_DC = 16;
const int BASE_LOCK_CHANCE = 20;

void GenerateLockOnObject(object oObject = OBJECT_SELF)
{
   if (GetLocalInt(oObject, "locked") != 1) return;
   if (GetLocalInt(GetArea(oObject), "unlocked") == 1) return;

   int iCR = GetLocalInt(oObject, "cr");

   int nLockChance = BASE_LOCK_CHANCE + (iCR*2);

   if (d100() <= nLockChance)
   {
       int nLockDC = BASE_LOCK_DC + iCR + d4();

       SetLockUnlockDC(oObject, nLockDC);
       SetLocked(oObject, TRUE);
   }
}

//void main(){}
