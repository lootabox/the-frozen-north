#include "inc_debug"
#include "nwnx_util"
#include "inc_loot"


// run via dm_runscript
// Kills everything in the area, as if you went and did it properly, and brings all the loot to you
// And tells you how much gold value there was in it

void KillCreature(object oCreature)
{
    SendMessageToPC(OBJECT_SELF, "Kill: " + GetName(oCreature));
    // Hopefully nothing lives this
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDamage(9999), oCreature);
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDamage(9999, DAMAGE_TYPE_DIVINE), oCreature);
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDamage(9999, DAMAGE_TYPE_PIERCING), oCreature);
}

void DelayedAction()
{
    int nOldInstructionLimit = NWNX_Util_GetInstructionLimit();
    NWNX_Util_SetInstructionLimit(52428888);
    object oArea = GetArea(OBJECT_SELF);
    SendDebugMessage("========= BEGIN FOR AREA: " + GetName(oArea) + " with tag " + GetTag(oArea) + " =========", TRUE);
    object oDev = OBJECT_SELF;
	LootDebugOutput();
    DeleteLocalObject(GetModule(), LOOT_DEBUG_AREA);
	SetLocalInt(GetModule(), LOOT_DEBUG_ENABLED, 0);
    DeleteLocalObject(GetModule(), "dev_lootvortex");
    
    object oTest = GetFirstObjectInArea(oArea);
    while (GetIsObjectValid(oTest))
    {
        if (GetResRef(oTest) == "_loot_container")
        {
            //SendMessageToPC(oDev, "Found loot container!");
            object oPersonalLoot = GetObjectByUUID(GetLocalString(oTest, "personal_loot_"+GetPCPublicCDKey(oDev, TRUE)));
            object oInvItem = GetFirstItemInInventory(oPersonalLoot);

            while (GetIsObjectValid(oInvItem))
            {
                DelayCommand(0.1, DestroyObject(oInvItem));
                oInvItem = GetNextItemInInventory(oPersonalLoot);
            }
            DelayCommand(0.5, DecrementLootAndDestroyIfEmpty(oDev, oTest, oPersonalLoot));
        }
        oTest = GetNextObjectInArea(oArea);
    }
    
    NWNX_Util_SetInstructionLimit(nOldInstructionLimit);
}

const int DO_CREATURES = 1;
const int DO_PLACEABLES = 1;

void main()
{
    object oDev = OBJECT_SELF;
    if (!GetIsDevServer())
    {
        SendMessageToAllDMs(GetName(oDev) + " tried to run dev_arealootval, but the server is not in developer mode");
        return;
    }

    if (!GetIsDeveloper(oDev))
    {
        SendMessageToAllDMs(GetName(oDev) + " tried to run dev_arealootval, but they are not a developer");
        return;
    }
    SendMessageToAllDMs(GetName(oDev) + " is running dev_arealootval in area: " + GetName(GetArea(oDev)));
    SendDiscordLogMessage(GetName(oDev) + " is running dev_arealootval in area: " + GetName(GetArea(oDev)));


    SetLocalObject(GetModule(), "dev_lootvortex", oDev);
	SetLocalInt(GetModule(), LOOT_DEBUG_ENABLED, 1);
	ResetLootDebug();

    // This is way easier than circumvention...
    int nOldInstructionLimit = NWNX_Util_GetInstructionLimit();
    NWNX_Util_SetInstructionLimit(52428888);

    object oArea = GetArea(oDev);
    object oTest = GetFirstObjectInArea(oArea);
	SetLocalObject(GetModule(), LOOT_DEBUG_AREA, oArea);
    while (GetIsObjectValid(oTest))
    {
        int nObjType = GetObjectType(oTest);
        if (nObjType == OBJECT_TYPE_CREATURE && DO_CREATURES)
        {
            if (!GetIsDead(oTest) && !GetIsPC(oTest))
            {
                DelayCommand(0.1, KillCreature(oTest));
                //DelayCommand(0.2, ExecuteScript("party_credit", oTest));
            }
        }
        else if (nObjType == OBJECT_TYPE_PLACEABLE && DO_PLACEABLES)
        {
            if (GetLocalInt(oTest, "cr") > 0 && GetResRef(oTest) != "_loot_container" && GetName(oTest) != "Personal Loot")
            {
                DelayCommand(0.2, ExecuteScript("party_credit", oTest));
            }
        }
        oTest = GetNextObjectInArea(oArea);
    }
    DelayCommand(10.0f, DelayedAction());
    NWNX_Util_SetInstructionLimit(nOldInstructionLimit);
}

