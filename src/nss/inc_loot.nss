#include "x2_inc_itemprop"
#include "inc_debug"
#include "inc_general"
#include "nwnx_player"
#include "nwnx_item"
#include "nwnx_visibility"
#include "util_i_math"
#include "nw_i0_plot"
#include "inc_treasure"
#include "inc_treasuremap"

// ===========================================================
// START CONSTANTS
// ===========================================================

// Seconds before loot is automatically destroyed.
const float LOOT_DESTRUCTION_TIME = 600.0;

// chance that a treasure will spawn at all out of 100
// This gets modified based on the difference between a monster's CR and the area CR
// Currently, the treasure drop rate as a percentage is:
// min(100, 20 * pow(2.0, ((MonsterCR - AreaCR)/2))
const float TREASURE_CHANCE = 30.0;
const float TREASURE_CHANCE_EXPONENT_DENOMINATOR = 2.0;

// chance that there won't be placeable treasure at all out of 100
const int NO_PLACEABLE_TREASURE_CHANCE = 30;

// Chance of this item type dropping
const int BASE_DEFAULT_WEIGHT = 2;
const int BASE_WEAPON_WEIGHT = 9;
const int BASE_ARMOR_WEIGHT = 2;
const int BASE_APPAREL_WEIGHT = 4;
const int BASE_SCROLL_WEIGHT = 3;
const int BASE_POTION_WEIGHT = 12;
const int BASE_MISC_WEIGHT = 10;

const int BASE_ADJUST_CHANCE = 25;

// The chance for one, two or three items to drop, specifically. This is out of 100.

const int CHANCE_ONE = 35;
const int CHANCE_TWO = 15;
const int CHANCE_THREE = 5;

// Lower these to decrease the base chance of getting certain tiers.
const int BASE_T1_WEIGHT = 2000;
const int BASE_T2_WEIGHT = 200;
const int BASE_T3_WEIGHT = 50;
const int BASE_T4_WEIGHT = 15;
const int BASE_T5_WEIGHT = 4;

// See the implementation for notes on what these are and how they work
const int T1_SIGMOID_MIDPOINT = 1;
const int T2_SIGMOID_MIDPOINT = 1;
const int T3_SIGMOID_MIDPOINT = 7;
const int T4_SIGMOID_MIDPOINT = 10;
const int T5_SIGMOID_MIDPOINT = 13;

// The string to play when there isn't loot available
const string NO_LOOT = "This container doesn't have any items.";

// Constants for placeable loot
// To use this, placeables should have a local string "treasure" set on them with a value of "low" "medium" or "high"
// The quality variables set quality_mult on containers, multiplying the effective Area CR of loot inside
// The quantity variables set quantity_mult on containers, multiplying the effective CHANCE_* constants for loot in there
// Manually setting these on the containers will override these values
// Doing things this way is nice because the entire module's loot can be changed by messing with these script constants
// Instead of going through blueprints to change variables like what was needed to implement this in the first place
const float TREASURE_HIGH_QUALITY = 1.0;
const float TREASURE_HIGH_QUANTITY = 3.0;
const float TREASURE_MEDIUM_QUALITY = 1.0;
const float TREASURE_MEDIUM_QUANTITY = 1.75;
const float TREASURE_LOW_QUALITY = 0.6;
const float TREASURE_LOW_QUANTITY = 1.0;

// CHANCE_X are multiplied by this for placeables that are destroyed (rather than opening the lock)
const float PLACEABLE_DESTROY_LOOT_PENALTY = 0.6;

// Percentage chances for various categories
// Needless to say, these sets should sum to 100
const int WEAPON_COMMON_CHANCE = 37;
const int WEAPON_UNCOMMON_CHANCE = 33;
const int WEAPON_RARE_CHANCE = 30;

const int APPAREL_ARMOR_COMMON_CHANCE = 42;
const int APPAREL_ARMOR_UNCOMMON_CHANCE = 33;
const int APPAREL_ARMOR_RARE_CHANCE = 25;

// And these don't need to sum to 100
const int UNIQUE_ITEM_CHANCE = 33;
const int MISC_CHANCE_TO_BE_JEWEL = 67;
const int RANDOM_WEAPON_IS_RANGED = 40;

// The real chance of a tiered pawnshop item to be unique is:
// UNIQUE_ITEM_CHANCE/100 * PAWNSHOP_CHANCE_TO_ALLOW_UNIQUE/100
// With both set at 33 that brings it to about 10.9%
// Pawnshops also typically stock lots of level appropriate random items that work like monster drops
// This applies ONLY to the fixed items of X tier
const int PAWNSHOP_CHANCE_TO_ALLOW_UNIQUE = 100;
const int STORE_RANDOM_T5_CHANCE = 3;


// ===========================================================
// START PROTOTYPES
// ===========================================================

// Select a tier Item. Specific Tier granted if nTier is 1-5.
// Valid types: "Armor", "Melee", "Range", "Misc, "Apparel"
// "Potion", "ScrollsDivine", "ScrollsArcane"
// The item returned by this function WILL BE IN A CONTAINER IN THE LOOT AREA.
// This does NOT MOVE OR MAKE A COPY OF THE ITEM in oContainer. oContainer is used to make sure the item in question
// is appropriate to generate in some situations (eg gems in stores are pointless)
// Use CopyTierItemToContainer to copy the return from this function to its final destination.
object SelectTierItem(int iCR, int iAreaCR, string sType = "", int nTier = 0, object oContainer=OBJECT_INVALID, int bNonUnique = FALSE);

// Copy oItem (which should be from SelectTierItem) to oContainer and correctly initialise it
object CopyTierItemToContainer(object oItem, object oContainer);

// Generate a tier Item. Specific Tier granted if nTier is 1-5.
// Valid types: "Armor", "Melee", "Range", "Misc, "Apparel"
// "Potion", "ScrollsDivine", "ScrollsArcane"
// An amalgamation of SelectTierItem and CopyTierItemToContainer for convenience.
object GenerateTierItem(int iCR, int iAreaCR, object oContainer, string sType = "", int nTier = 0, int bNonUnique = FALSE);

// Open a personal loot. Called from a containing object.
void OpenPersonalLoot(object oContainer, object oPC);



// ===========================================================
// DEBUGGING
// ===========================================================

// To turn on, set LOOT_DEBUG_ENABLED on the module to 1.
// This also requires the server in dev mode

// Various debugging variables - all should go on the module
const string LOOT_DEBUG_ENABLED = "dev_loot_debug";
// Set on the module, should be equal to the expected number of items rolled by the creature that is dying
const string LOOT_DEBUG_DROP_CHANCE_MULT = "dev_loot_debug_drop_chance_mult";
// These are all floats, and are the expected amount of gold of items of the given tier generated
const string LOOT_DEBUG_OUTPUT = "dev_loot_debug_t";
const string LOOT_DEBUG_GOLD = "dev_loot_debug_gold";
// If set, only track loot generated in this area (to avoid picking up other loot system calls for anything unrelated)
const string LOOT_DEBUG_AREA = "dev_loot_debug_area";
// In debugging, DetermineTier sets its weights on the module
const string LOOT_DEBUG_T1_WEIGHT = "dev_loot_debug_t1_weight";
const string LOOT_DEBUG_T2_WEIGHT = "dev_loot_debug_t2_weight";
const string LOOT_DEBUG_T3_WEIGHT = "dev_loot_debug_t3_weight";
const string LOOT_DEBUG_T4_WEIGHT = "dev_loot_debug_t4_weight";
const string LOOT_DEBUG_T5_WEIGHT = "dev_loot_debug_t5_weight";
// Values of given tier/item type combos are stored to avoid needless iterating over inventories
// "dev_loot_debug_tX_<type>_value"

// Gets the average value of items of the given tier and item type
float GetAverageLootValueOfItem(int nTier, string sType);

// Whether or not to track loot probabilities. Enabling this adds quite a lot of extra float calculations
int ShouldDebugLoot();

// Output the loot tracker's numbers
void LootDebugOutput();

// Reset the loot tracker.
void ResetLootDebug();

// ====================
// OWINGS
// ====================

// "Owings" and "tracked debt" (because it feels bad when someone gets all the bad loot)
// A PC tracks how much each henchman and other player "owes" them (based on gold value disparity)
// -> Use this to weight the probability of who gets what items
// The PC-henchman owings are tracked in the PC BIC DB
// PC-PC owings are, at least for now, tracked in a serverside Cdkey-Cdkey db
// This might be a bit weird but permanently tracking characters seems like a significantly more difficult problem

// For the sake of implementation, each henchman/PC in the party starts has 1000 "points"
// If they "owe" some other party member(s) loot, they give some of their points to the people they owe to
// Then roll a d(total number of points) and see whose band the roll lands in, and they get the item

// This falls down when one party member tries to give out more than their 1000 "points"
// ... in which case their points need to instead be distributed relative to the people demanding them
// eg if three people demand 100/400/800 points from me (total 1300), first person gets 100/1.3, second gets 400/1.3, third gets 800/1.3

// Return the amount of gold value oDebtor owes oReceiver.
// If oReceiver instead owes oDebtor, the value returned is negative.
int GetOwedGoldValue(object oReceiver, object oDebtor);

// Return how many "owing points" to transfer from oDebtor to oReceiver for getting an item of nItemGoldValue
// If oReceiver owes oDebtor value, this will be negative.
int GetLootWeightingTransferBasedOnOwings(object oReceiver, object oDebtor, int nItemGoldValue);

// Increase the debt of oDebtor to oReceiver by nAmount.
void AdjustOwedGoldValue(object oReceiver, object oDebtor, int nAmount);

// Whether or not to write debug messages about loot owing to the log
const int LOOT_OWING_DEBUG = 1;

// ===========================================================
// START FUNCTIONS
// ===========================================================

const string PERSONAL_LOOT_GOLD_AMOUNT = "personal_loot_gold";

// Return the amount of gold value oDebtor owes oReceiver.
// If oReceiver instead owes oDebtor, the value returned is negative.
int GetOwedGoldValue(object oReceiver, object oDebtor)
{
    if (!GetIsPC(oReceiver) && !GetIsPC(oDebtor))
    {
        int nSaved = GetCampaignInt("lootowings", "hench_" + GetTag(oReceiver) + "-" + GetTag(oDebtor));
        if (nSaved == 0)
        {
            nSaved = GetCampaignInt("lootowings", "hench_" + GetTag(oDebtor) + "-" + GetTag(oReceiver)) * -1;
        }
        return nSaved;
    }
    if (GetIsPC(oReceiver) && GetIsPC(oDebtor))
    {
        int nSaved = GetCampaignInt("lootowings", GetPCPublicCDKey(oReceiver) + "-" + GetPCPublicCDKey(oDebtor));
        if (nSaved == 0)
        {
            nSaved = GetCampaignInt("lootowings", GetPCPublicCDKey(oDebtor) + "-" + GetPCPublicCDKey(oReceiver)) * -1;
        }
        return nSaved;
    }
    // If we get here, exactly one of oDebtor and oReceiver is a PC and the other is a henchman
    object oPC;
    object oHen;
    if (GetIsPC(oReceiver))
    {
        oPC = oReceiver;
        oHen = oDebtor;
    }
    else
    {
        oPC = oDebtor;
        oHen = oReceiver;
    }
    // Check the PC's BIC db for the amount
    int nAmt = SQLocalsPlayer_GetInt(oPC, "lootowing_" + GetTag(oHen));
    // This is how much the hench owes the player, make it negative if the function was called the other way round
    if (oDebtor == oPC)
    {
        nAmt *= -1;
    }
    return nAmt;
}

// Return how many "owing points" to transfer from oDebtor to oReceiver for getting an item of nItemGoldValue
// If oReceiver owes oDebtor value, this will be negative.
int GetLootWeightingTransferBasedOnOwings(object oReceiver, object oDebtor, int nItemGoldValue)
{
    int nDebt = GetOwedGoldValue(oReceiver, oDebtor);
    // This is the fastest outcome, and will cause dividing by zero later if not dealt with now
    if (nDebt == 0)
    {
        return 0;
    }
    if (nDebt < 0)
    {
        return -1*GetLootWeightingTransferBasedOnOwings(oDebtor, oReceiver, nItemGoldValue);
    }
    // Base premise:
    // points to transfer when owing = 10 + (itemvalue/min(debt, 22000))^1.5 * 55
    // min(debt, 22000) is because 22000 is the highest possible in one item (upper value bracket of t5)
    // adding 10 means the split is 60/40 for all items
    // the exponential expression means that items are much more skewed the closer they are to the debt size
    // In TFN item gold value does not scale linearly with "desirableness" and this is an attempt to capture that

    // If the item value > debt size, calc how much it exceeds by and subtract that from the item value
    // this will mean that the curve mirrors as value passes debt size and rapidly drops down to more even values
    // as the debt is exceeded
    if (nDebt < nItemGoldValue)
    {
        // (but don't make the item value go negative)
        nItemGoldValue = max(0, nDebt - (nItemGoldValue - nDebt));
    }
    float fItemGoldValue = IntToFloat(nItemGoldValue);
    float fDebt = IntToFloat(min(nDebt, 22000));
    float fTransfer = 100 + (pow(fItemGoldValue/fDebt, 1.5) * 850);
    return FloatToInt(fTransfer);
}

// Increase the debt of oDebtor to oReceiver by nAmount.
void AdjustOwedGoldValue(object oReceiver, object oDebtor, int nAmount)
{
    if (!GetIsPC(oReceiver) && !GetIsPC(oDebtor))
    {
        string sVar = "hench_" + GetTag(oReceiver) + "-" + GetTag(oDebtor);
        int nSaved = GetCampaignInt("lootowings", sVar);
        if (nSaved == 0)
        {
            sVar = "hench_" + GetTag(oDebtor) + "-" + GetTag(oReceiver);
            nSaved = GetCampaignInt("lootowings", sVar);
            nAmount *= -1;
        }
        if (LOOT_OWING_DEBUG)
        {
            WriteTimestampedLogEntry("Added " + IntToString(nAmount) + " to the amount " + GetName(oDebtor) + " owes " + GetName(oReceiver) + ": now " + IntToString(nSaved + nAmount));
        }
        SetCampaignInt("lootowings", sVar, nSaved + nAmount);
        return;
    }
    if (GetIsPC(oReceiver) && GetIsPC(oDebtor))
    {
        // Figure out which one is being used
        string sVar = GetPCPublicCDKey(oReceiver) + "-" + GetPCPublicCDKey(oDebtor);
        int nSaved = GetCampaignInt("lootowings", sVar);
        if (nSaved == 0)
        {
            sVar = GetPCPublicCDKey(oDebtor) + "-" + GetPCPublicCDKey(oReceiver);
            nSaved = GetCampaignInt("lootowings", sVar);
            nAmount *= -1;
        }
        if (LOOT_OWING_DEBUG)
        {
            WriteTimestampedLogEntry("Added " + IntToString(nAmount) + " to the amount " + GetName(oDebtor) + " owes " + GetName(oReceiver) + ": now " + IntToString(nSaved + nAmount));
        }
        SetCampaignInt("lootowings", sVar, nSaved + nAmount);
        return;
    }
    // If we get here, exactly one of oDebtor and oReceiver is a PC and the other is a henchman
    object oPC;
    object oHen;
    if (GetIsPC(oReceiver))
    {
        oPC = oReceiver;
        oHen = oDebtor;
    }
    else
    {
        oPC = oDebtor;
        oHen = oReceiver;
        nAmount *= -1;
    }
    // Check the PC's BIC db for the amount
    int nSaved = SQLocalsPlayer_GetInt(oPC, "lootowing_" + GetTag(oHen));
    if (LOOT_OWING_DEBUG)
    {
        WriteTimestampedLogEntry("Added " + IntToString(nAmount) + " to the amount " + GetName(oHen) + " owes " + GetName(oPC) + ": now " + IntToString(nSaved + nAmount));
    }
    SQLocalsPlayer_SetInt(oPC, "lootowing_" + GetTag(oHen), nSaved + nAmount);
}

// ---------------------------------------------------------
// This function is used to determine the tier of the drop.
// ---------------------------------------------------------
string DetermineTier(int iCR, int iAreaCR, string sType = "")
{
    float fCR = IntToFloat(iCR);
    string sTier;

    //SendDebugMessage("Loot fCR: "+FloatToString(fCR));
    // These functions look demented, but were designed with a fairly large amount of reasoning in mind
    // This also discusses the issues with the significantly simpler system that it replaced
    // https://docs.google.com/document/d/1t451EgutNToXGVbuQGHraBaefI8TsWlcWbqXDpU-HA0
    // As the person that spent a few hours coming up with them, I would strongly encourage
    // a detailed discussion of what about the design of these is wrong before messing with them!
    int nT1Weight = FloatToInt(BASE_T1_WEIGHT * fmax(0.0, ((68.0 + atan((iAreaCR - T1_SIGMOID_MIDPOINT) * 0.6))/158.0)));
    int nT2Weight = FloatToInt(BASE_T2_WEIGHT * iAreaCR * fmax(0.0, ((68.0 + atan((iAreaCR - T2_SIGMOID_MIDPOINT) * 0.6))/158.0)));
    int nT3Weight = FloatToInt(BASE_T3_WEIGHT * iAreaCR * fmax(0.0, ((68.0 + atan((iAreaCR - T3_SIGMOID_MIDPOINT) * 0.6))/158.0)));
    int nT4Weight = FloatToInt(BASE_T4_WEIGHT * iAreaCR * fmax(0.0, ((68.0 + atan((iAreaCR - T4_SIGMOID_MIDPOINT) * 0.6))/158.0)));
    int nT5Weight = FloatToInt(BASE_T5_WEIGHT * iAreaCR * fmax(0.0, ((68.0 + atan((iAreaCR - T5_SIGMOID_MIDPOINT) * 0.6))/158.0)));

   int nCombinedWeight = 0;

// If any of these happen to be less than 0, make it 0

   if (nT1Weight < 0) nT1Weight = 0;
   if (nT2Weight < 0) nT2Weight = 0;
   if (nT3Weight < 0) nT3Weight = 0;
   if (nT4Weight < 0) nT4Weight = 0;
   if (nT5Weight < 0) nT5Weight = 0;

    if (ShouldDebugLoot())
    {
        SetLocalInt(GetModule(), LOOT_DEBUG_T1_WEIGHT, nT1Weight);
        SetLocalInt(GetModule(), LOOT_DEBUG_T2_WEIGHT, nT2Weight);
        SetLocalInt(GetModule(), LOOT_DEBUG_T3_WEIGHT, nT3Weight);
        SetLocalInt(GetModule(), LOOT_DEBUG_T4_WEIGHT, nT4Weight);
        SetLocalInt(GetModule(), LOOT_DEBUG_T5_WEIGHT, nT5Weight);

        SendDebugMessage("Loot T1Weight: "+IntToString(nT1Weight));
        SendDebugMessage("Loot T2Weight: "+IntToString(nT2Weight));
        SendDebugMessage("Loot T3Weight: "+IntToString(nT3Weight));
        SendDebugMessage("Loot T4Weight: "+IntToString(nT4Weight));
        SendDebugMessage("Loot T5Weight: "+IntToString(nT5Weight));
    }


   SendDebugMessage("Loot T1Weight: "+IntToString(nT1Weight));
   SendDebugMessage("Loot T2Weight: "+IntToString(nT2Weight));
   SendDebugMessage("Loot T3Weight: "+IntToString(nT3Weight));
   SendDebugMessage("Loot T4Weight: "+IntToString(nT4Weight));
   SendDebugMessage("Loot T5Weight: "+IntToString(nT5Weight));

   nCombinedWeight = nT1Weight + nT2Weight + nT3Weight + nT4Weight + nT5Weight;
   //SendDebugMessage("Combined: "+IntToString(nCombinedWeight));

   // This is better than crashing out with a TMI if it can happen for any reason
   // (this happened when trying to add the sigmoids for the first time)
   if (nCombinedWeight == 0)
   {
       SendDebugMessage("ERROR: Combined weight for DetermineTier at CR " + IntToString(iCR) + " and area CR " + IntToString(iAreaCR) + " resulted in a weight sum of 0!", TRUE);
       return "T1";
   }

   int nTierRoll = Random(nCombinedWeight)+1;
   //SendDebugMessage("Roll: "+IntToString(nTierRoll));

   while (TRUE)
   {
        nTierRoll = nTierRoll - nT1Weight;
        if (nTierRoll <= 0) {sTier = "T1";break;}

        nTierRoll = nTierRoll - nT2Weight;
        if (nTierRoll <= 0) {sTier = "T2";break;}

        nTierRoll = nTierRoll - nT3Weight;
        if (nTierRoll <= 0) {sTier = "T3";break;}

        nTierRoll = nTierRoll - nT4Weight;
        if (nTierRoll <= 0) {sTier = "T4";break;}

        nTierRoll = nTierRoll - nT5Weight;
        if (nTierRoll <= 0) {sTier = "T5";break;}
    }

    //SendDebugMessage("Chosen Tier: "+sTier);

    int nCount = GetLocalInt(GetModule(), sTier);
    SetLocalInt(GetModule(), sTier, nCount+1);

    return sTier;
}

object SelectTierItem(int iCR, int iAreaCR, string sType = "", int nTier = 0, object oContainer=OBJECT_INVALID, int bNonUnique = FALSE)
{
    string sTier = DetermineTier(iCR, iAreaCR, sType);
    string sRarity = "";
    string sNonUnique = "";

    // Loot debug ignores this as type is rolled in GenerateLoot below

// Given no type, generate a random one.
    if (sType == "")
    {
        switch(Random(6))
        {
           case 0: sType = "Misc"; break;
           case 1: sType = "Scrolls"; break;
           case 2: sType = "Weapon"; break;
           case 3: sType = "Armor"; break;
           case 4: sType = "Apparel"; break;
           case 5: sType = "Potions"; break;
        }
    }


// These types are special cases because they have rarities.
    if (sType == "Range" || sType == "Melee" || sType == "Weapon" || sType == "Armor" || sType == "Apparel")
    {
        if (sType == "Melee" || sType == "Range" || sType == "Weapon")
        {
            int nRoll = d100();
            if (nRoll <= WEAPON_COMMON_CHANCE)
            {
                sRarity = "Common";
            }
            else
            {
                nRoll -= WEAPON_COMMON_CHANCE;
                if (nRoll <= WEAPON_UNCOMMON_CHANCE)
                {
                    sRarity = "Uncommon";
                }
                else
                {
                    sRarity = "Rare";
                }
            }
        }
        else
        {
            int nRoll = d100();
            if (nRoll <= APPAREL_ARMOR_COMMON_CHANCE)
            {
                sRarity = "Common";
            }
            else
            {
                nRoll -= APPAREL_ARMOR_COMMON_CHANCE;
                if (nRoll <= APPAREL_ARMOR_UNCOMMON_CHANCE)
                {
                    sRarity = "Uncommon";
                }
                else
                {
                    sRarity = "Rare";
                }
            }
        }
    }


// These types can have either a unique, or non-unique
    if (sType == "Range" || sType == "Weapon" || sType == "Armor" || sType == "Melee" || sType == "Potions")
    {
        if (d100() > UNIQUE_ITEM_CHANCE)
        {
            sNonUnique = "NonUnique";
        }
    }

    if (bNonUnique)
    {
        sNonUnique = "NonUnique";
    }

// 2 out of 3 misc items will always be gems/jewelry
// Unless you're a shop, in which case this is just wasted UI space because there's no reason to ever buy these items
    if (sType == "Misc" && d100() <= MISC_CHANCE_TO_BE_JEWEL && GetObjectType(oContainer) != OBJECT_TYPE_STORE)
    {
        sType = "Jewels";
    }



// never NU
    if (sType == "Misc" || sType == "Apparel" || sType == "Scrolls" || sType == "Jewels")
        sNonUnique = "";

    if (sType == "Weapon")
    {
        sType = "Melee";
// chance of this being a range weapon
        if (d100() <= RANDOM_WEAPON_IS_RANGED) sType = "Range";
    }

    if (nTier > 0)
    {
        switch (nTier)
        {
           case 1: sTier = "T1"; break;
           case 2: sTier = "T2"; break;
           case 3: sTier = "T3"; break;
           case 4: sTier = "T4"; break;
           case 5: sTier = "T5"; break;
        }
    }

    object oChest = GetObjectByTag("_"+sType+sRarity+sTier+sNonUnique);
// we'll use the non-unique chest if the unique container, if applicable simply don't exist
    if (!GetIsObjectValid(oChest))
    {
        //SendDebugMessage("_"+sType+sRarity+sTier+sNonUnique+" not found, falling back to NU", TRUE);
        oChest = GetObjectByTag("_"+sType+sRarity+sTier+"NonUnique");
    }

// chest still invalid at that point? return
    if (!GetIsObjectValid(oChest)) return OBJECT_INVALID;

    int nRandom = Random(StringToInt(GetDescription(oChest)));
    object oItem = GetFirstItemInInventory(oChest);

    //SendDebugMessage("Chosen chest: "+GetName(oChest)+"Count: "+GetDescription(oChest)+" Selected: "+IntToString(nRandom), TRUE);

    while (nRandom)
    {
        nRandom--;
        oItem = GetNextItemInInventory(oChest);
    }

    if (GetPlotFlag(oItem) && GetObjectType(oContainer) == OBJECT_TYPE_STORE)
    {
        return OBJECT_INVALID; // do not allow plot items to be created on stores
    }

    int nCount = GetLocalInt(GetModule(), sType);
    SetLocalInt(GetModule(), sType, nCount+1);
    //WriteTimestampedLogEntry("SelectTierItem type " + sType + " " + sTier + " -> " + GetName(oItem));
    return oItem;
}


// ---------------------------------------------------------
// This function is used to generate a tier item.
// ---------------------------------------------------------
object GenerateTierItem(int iCR, int iAreaCR, object oContainer, string sType = "", int nTier = 0, int bNonUnique = FALSE)
{
    object oItem = SelectTierItem(iCR, iAreaCR, sType, nTier, oContainer, bNonUnique);
    object oNewItem = CopyTierItemToContainer(oItem, oContainer);
    return oNewItem;
}

object CopyTierItemToLocation(object oItem, location lTarget)
{
    if (!GetIsObjectValid(oItem))
    {
        return OBJECT_INVALID;
    }
    object oNewItem = CopyObject(oItem, lTarget, OBJECT_INVALID, "", TRUE);


    //int nRarityCount = GetLocalInt(GetModule(), sRarity);
    //SetLocalInt(GetModule(), sRarity, nRarityCount+1);

// Set a stack size. Don't go above 50, due to certain stack sizes.
    int nBaseType = GetBaseItemType(oNewItem);
    if (nBaseType == BASE_ITEM_THROWINGAXE || nBaseType == BASE_ITEM_DART || nBaseType == BASE_ITEM_SHURIKEN || nBaseType == BASE_ITEM_ARROW || nBaseType == BASE_ITEM_BULLET || nBaseType == BASE_ITEM_BOLT) SetItemStackSize(oNewItem, Random(45)+1);

    // Boomerang items should always generate as stack size 1
    if (GetItemHasItemProperty(oNewItem, ITEM_PROPERTY_BOOMERANG))
    {
        SetItemStackSize(oNewItem, 1);
    }

    // Set visual transforms, and do the rest if it wasn't done for any reason
    InitializeItem(oNewItem);

    return oNewItem;
}

object CopyTierItemToContainer(object oItem, object oContainer)
{
    if (!GetIsObjectValid(oItem))
    {
        return OBJECT_INVALID;
    }
    if (!GetIsObjectValid(oContainer))
    {
        return OBJECT_INVALID;
    }
    object oNewItem = CopyItem(oItem, oContainer, TRUE);


    //int nRarityCount = GetLocalInt(GetModule(), sRarity);
    //SetLocalInt(GetModule(), sRarity, nRarityCount+1);

// Set a stack size. Don't go above 50, due to certain stack sizes.
    int nBaseType = GetBaseItemType(oNewItem);
    if (nBaseType == BASE_ITEM_THROWINGAXE || nBaseType == BASE_ITEM_DART || nBaseType == BASE_ITEM_SHURIKEN || nBaseType == BASE_ITEM_ARROW || nBaseType == BASE_ITEM_BULLET || nBaseType == BASE_ITEM_BOLT) SetItemStackSize(oNewItem, Random(45)+1);

    // Boomerang items should always generate as stack size 1
    if (GetItemHasItemProperty(oNewItem, ITEM_PROPERTY_BOOMERANG))
    {
        SetItemStackSize(oNewItem, 1);
    }

    // Set visual transforms, and do the rest if it wasn't done for any reason
    InitializeItem(oNewItem);

    return oNewItem;
}

// ---------------------------------------------------------
// Generates loot. Typically used for creatures or containers.
// ---------------------------------------------------------

object SelectLoot(object oLootSource, object oDestinationContainer=OBJECT_INVALID)
{

   if (GetLocalInt(GetModule(), "treasure_ready") != 1)
   {
       SendMessageToAllPCs("Treasure isn't ready. No treasure will be generated.");
       return OBJECT_INVALID;
   }

   if (GetLocalInt(GetModule(), "treasure_tainted") == 1)
   {
       SendMessageToAllPCs("Treasure is tainted. No treasure will be generated.");
       return OBJECT_INVALID;
   }

   if (!GetIsObjectValid(oDestinationContainer))
   {
       oDestinationContainer = oLootSource;
   }

   int iCR = GetLocalInt(oLootSource, "cr");
   int iAreaCR = GetLocalInt(oLootSource, "area_cr");

// Add all the weights
   int nCombinedWeight = 0;

   int nMiscWeight = BASE_MISC_WEIGHT;
   int nScrollsWeight = BASE_SCROLL_WEIGHT;
   int nPotionsWeight = BASE_POTION_WEIGHT;
   int nWeaponWeight = BASE_WEAPON_WEIGHT;
   int nArmorWeight = BASE_ARMOR_WEIGHT;
   int nApparelWeight = BASE_APPAREL_WEIGHT;

// If any of these happen to be less than 0, make it 0
   if (nMiscWeight < 0) nMiscWeight = 0;
   if (nScrollsWeight < 0) nScrollsWeight = 0;
   if (nPotionsWeight < 0) nPotionsWeight = 0;
   if (nWeaponWeight < 0) nWeaponWeight = 0;
   if (nArmorWeight < 0) nArmorWeight = 0;
   if (nApparelWeight < 0) nApparelWeight = 0;

   nCombinedWeight = nMiscWeight + nScrollsWeight + nPotionsWeight + nWeaponWeight + nArmorWeight + nApparelWeight;

   int nItemRoll = Random(nCombinedWeight)+1;
   object oItem;
   while (TRUE)
   {
       nItemRoll = nItemRoll - nMiscWeight;
       if (nItemRoll <= 0) {oItem = SelectTierItem(iCR, iAreaCR, "Misc", 0, oDestinationContainer);break;}

       nItemRoll = nItemRoll - nScrollsWeight;
       if (nItemRoll <= 0) {oItem = SelectTierItem(iCR, iAreaCR, "Scrolls", 0, oDestinationContainer);break;}

       nItemRoll = nItemRoll - nPotionsWeight;
       if (nItemRoll <= 0) {oItem = SelectTierItem(iCR, iAreaCR, "Potions", 0, oDestinationContainer);break;}

       nItemRoll = nItemRoll - nWeaponWeight;
       if (nItemRoll <= 0) {oItem = SelectTierItem(iCR, iAreaCR, "Weapon", 0, oDestinationContainer);break;}

       nItemRoll = nItemRoll - nArmorWeight;
       if (nItemRoll <= 0) {oItem = SelectTierItem(iCR, iAreaCR, "Armor", 0, oDestinationContainer);break;}

       nItemRoll = nItemRoll - nApparelWeight;
       if (nItemRoll <= 0) {oItem = SelectTierItem(iCR, iAreaCR, "Apparel", 0, oDestinationContainer);break;}
   }

    if (ShouldDebugLoot())
    {
        object oModule = GetModule();
        object oTargetArea = GetLocalObject(oModule, LOOT_DEBUG_AREA);
        if (!GetIsObjectValid(oTargetArea) || oTargetArea == GetArea(oDestinationContainer))
        {
            float fChanceForNoLootMultiplier = GetLocalFloat(oModule, LOOT_DEBUG_DROP_CHANCE_MULT);
            float fCombinedWeight = IntToFloat(nCombinedWeight);
            // Doing all this division every time is not ideal, but...
            // Someday someone might want to make a version that calculates expected values
            // outside of the default loot item type proportions
            // and so making the gold-fetch function on a per-itemtype basis seemed sensible
            float fMiscChance = IntToFloat(BASE_MISC_WEIGHT)/fCombinedWeight;
            float fScrollChance = IntToFloat(BASE_SCROLL_WEIGHT)/fCombinedWeight;
            float fPotionChance = IntToFloat(BASE_POTION_WEIGHT)/fCombinedWeight;
            float fWeaponChance = IntToFloat(BASE_WEAPON_WEIGHT)/fCombinedWeight;
            float fArmorChance = IntToFloat(BASE_ARMOR_WEIGHT)/fCombinedWeight;
            float fApparelChance = IntToFloat(BASE_APPAREL_WEIGHT)/fCombinedWeight;


            int nT1Weight = GetLocalInt(oModule, LOOT_DEBUG_T1_WEIGHT);
            int nT2Weight = GetLocalInt(oModule, LOOT_DEBUG_T2_WEIGHT);
            int nT3Weight = GetLocalInt(oModule, LOOT_DEBUG_T3_WEIGHT);
            int nT4Weight = GetLocalInt(oModule, LOOT_DEBUG_T4_WEIGHT);
            int nT5Weight = GetLocalInt(oModule, LOOT_DEBUG_T5_WEIGHT);

            float fWeightSum = IntToFloat(nT1Weight + nT2Weight + nT3Weight + nT4Weight + nT5Weight);

            float fT1Prob = IntToFloat(nT1Weight)/fWeightSum;
            float fT2Prob = IntToFloat(nT2Weight)/fWeightSum;
            float fT3Prob = IntToFloat(nT3Weight)/fWeightSum;
            float fT4Prob = IntToFloat(nT4Weight)/fWeightSum;
            float fT5Prob = IntToFloat(nT5Weight)/fWeightSum;

            int nItemTypeIndex;
            int nTier;
            for (nItemTypeIndex=0; nItemTypeIndex <= 5; nItemTypeIndex++)
            {
                string sType;
                float fChance;
                // Ugly, but probably better than using a SetLocalFloat based lookup system
                switch (nItemTypeIndex)
                {
                    case 0: { sType="Misc";     fChance=fMiscChance;    break; }
                    case 1: { sType="Scrolls";  fChance=fScrollChance;  break; }
                    case 2: { sType="Potions";  fChance=fPotionChance;  break; }
                    case 3: { sType="Weapon";   fChance=fWeaponChance;  break; }
                    case 4: { sType="Armor";    fChance=fArmorChance;   break; }
                    case 5: { sType="Apparel";  fChance=fApparelChance; break; }
                }
                for (nTier=1; nTier<=5; nTier++)
                {
                    float fTierChance;
                    switch (nTier)
                    {
                        case 1: { fTierChance=fT1Prob; break; }
                        case 2: { fTierChance=fT2Prob; break; }
                        case 3: { fTierChance=fT3Prob; break; }
                        case 4: { fTierChance=fT4Prob; break; }
                        case 5: { fTierChance=fT5Prob; break; }
                    }
                    float fGold = GetAverageLootValueOfItem(nTier, sType);
                    float fProb = fTierChance*fChance*fChanceForNoLootMultiplier;
                    float fContribution = fGold*fProb;
                    string sVar = LOOT_DEBUG_OUTPUT + IntToString(nTier);
                    SetLocalFloat(oModule, sVar, GetLocalFloat(oModule, sVar) + fContribution);
                    sVar = sVar + "_" + sType;
                    SetLocalFloat(oModule, sVar, GetLocalFloat(oModule, sVar) + fContribution);
                    sVar = LOOT_DEBUG_OUTPUT + IntToString(nTier) + "_numitems";
                    SetLocalFloat(oModule, sVar, GetLocalFloat(oModule, sVar) + fProb);
                }
            }
        }
    }

    return oItem;
}

object GenerateLoot(object oLootSource, object oDestinationContainer=OBJECT_INVALID)
{
    if (!GetIsObjectValid(oDestinationContainer))
    {
        oDestinationContainer = OBJECT_SELF;
    }
    if (!GetHasInventory(oDestinationContainer))
    {
        return OBJECT_INVALID;
    }
    object oItem = SelectLoot(oLootSource, oDestinationContainer);
    return CopyTierItemToContainer(oItem, oDestinationContainer);
}

void DecrementLootAndDestroyIfEmpty(object oOpener, object oLootParent, object oPersonalLoot)
{

// do not continue unless there are still items
    if (GetIsObjectValid(GetFirstItemInInventory(oPersonalLoot))) return;

// play a closing sound
    //AssignCommand(oOpener, PlaySound("as_sw_clothcl1"));

    int nUnlooted = GetLocalInt(oLootParent, "unlooted")-1;

// Decrement number of players who looted this, and destroy the loot container.
    SetLocalInt(oLootParent, "unlooted", nUnlooted);
    DestroyObject(oPersonalLoot);

    int bIsTreasure = GetStringLeft(GetResRef(oLootParent), 6) == "treas_";

    // Hide lootbags for players that have taken all their stuff
    if (!bIsTreasure)
    {
        NWNX_Visibility_SetVisibilityOverride(oOpener, oLootParent, NWNX_VISIBILITY_HIDDEN);
    }
    else
    {
        // Placeables instead become unusable
        NWNX_Player_SetPlaceableUsable(oOpener, oLootParent, FALSE);
    }

// 0 or less unlooted means everyone has already looted this.
    if (nUnlooted <= 0)
    {
        SetPlotFlag(oLootParent, FALSE);

        if (bIsTreasure)
        {
            // Assume this is a placeable treasure, close it then destroy it.
            // Mysteriously disappearing placeables is a bit strange
            //AssignCommand(oLootParent, ActionPlayAnimation(ANIMATION_PLACEABLE_CLOSE));
            //DestroyObject(oLootParent, 2.5);

            // Stay open, but be unusuable
            SetUseableFlag(oLootParent, FALSE);

        }
        else
        {
            DestroyObject(oLootParent);
            // Assume this is a loot bag, destroy
        }
    }
}


// ---------------------------------------------------------
// This function is used to access a loot container.
// ---------------------------------------------------------
void OpenPersonalLoot(object oContainer, object oPC)
{
// don't do anything if not a PC
    if (!GetIsPC(oPC)) return;

// Get the personal container
    object oPersonalLoot = GetObjectByUUID(GetLocalString(oContainer, "personal_loot_"+GetPCPublicCDKey(oPC, TRUE)));

    int nGold = GetLocalInt(oPersonalLoot, PERSONAL_LOOT_GOLD_AMOUNT);
    if (nGold > 0)
    {
        AssignCommand(oContainer, ActionPlayAnimation(ANIMATION_PLACEABLE_OPEN));
        GiveGoldToCreature(oPC, nGold);
        DeleteLocalInt(oPersonalLoot, PERSONAL_LOOT_GOLD_AMOUNT);
        NWNX_Player_PlaySound(oPC, "it_coins", oPC);
    }

// if the loot container doesn't exist, give a message
    if (oPersonalLoot == OBJECT_INVALID)
    {
        if (nGold <= 0)
        {
            FloatingTextStringOnCreature(NO_LOOT, oPC, FALSE);
            int bIsTreasure = GetStringLeft(GetResRef(oContainer), 6) == "treas_";

            // Hide the lootbag
            if (!bIsTreasure)
            {
                NWNX_Visibility_SetVisibilityOverride(oPC, oContainer, NWNX_VISIBILITY_HIDDEN);
            }
            else
            {
                // Flag placeable unusable for this NPC
                NWNX_Player_SetPlaceableUsable(oPC, oContainer, FALSE);
            }
        }
    }
// if there are no items in it, destroy it immediately and do the logic
    else if (!GetIsObjectValid(GetFirstItemInInventory(oPersonalLoot)))
    {
        if (nGold <= 0)
        {
            FloatingTextStringOnCreature(NO_LOOT, oPC, FALSE);
            DecrementLootAndDestroyIfEmpty(oPC, oContainer, oPersonalLoot);
        }
        if (nGold > 0)
        {
            DelayCommand(1.0, DecrementLootAndDestroyIfEmpty(oPC, oContainer, oPersonalLoot));
        }
    }
    else
    {
        NWNX_Player_ForcePlaceableInventoryWindow(oPC, oPersonalLoot);
    }
}


int DetermineGoldFromCR(int iCR, int nMultiplier=1)
{
    if (iCR < 1) iCR = 1;
    int iResult = nMultiplier * (3+d3(iCR));

    if (d10() == 10) iResult = iResult*2; // 10% chance to double gold
    if (ShouldDebugLoot())
    {
        float fAvg = IntToFloat(nMultiplier * (3 + (iCR * 2)));
        fAvg *= 1.1;
        float fChanceForNoLootMultiplier = GetLocalFloat(GetModule(), LOOT_DEBUG_DROP_CHANCE_MULT);
        fAvg *= fChanceForNoLootMultiplier;
        SetLocalFloat(GetModule(), LOOT_DEBUG_GOLD, GetLocalFloat(GetModule(), LOOT_DEBUG_GOLD) + fAvg);
    }
    return iResult;
}

int ShouldDebugLoot()
{
    if (GetIsDevServer() && GetLocalInt(GetModule(), LOOT_DEBUG_ENABLED))
    {
        return TRUE;
    }
    return FALSE;
}

int GetIdentifiedItemCost(object oItem)
{
    int nState = GetIdentified(oItem);
    if (!nState)
    {
        SetIdentified(oItem, TRUE);
    }
    int nVal = GetGoldPieceValue(oItem);
    SetIdentified(oItem, nState);
    return nVal;
}

float GetAverageLootValueOfItem(int nTier, string sType)
{
    //"dev_loot_debug_tX_<type>_value"
    string sVar = "dev_loot_debug_t" + IntToString(nTier) + "_" + sType + "_value";
    float fVal = GetLocalFloat(GetModule(), sVar);
    if (fVal > 0.0)
    {
        return fVal;
    }
    // If it's not saved, it's calculation time

    // "Weapon" chests don't exist and are instead just an amalgamation of Melee + Range
    if (sType == "Weapon")
    {
        float fRangedProportion = IntToFloat(RANDOM_WEAPON_IS_RANGED)/100.0;
        float fMeleeProportion = 1.0 - fRangedProportion;
        float fRet = (fMeleeProportion * GetAverageLootValueOfItem(nTier, "Melee")) + (fRangedProportion * GetAverageLootValueOfItem(nTier, "Range"));
        SetLocalFloat(GetModule(), sVar, fRet);
        return fRet;
    }

    float fCommonChance = 1.0;
    float fUncommonChance = 0.0;
    float fRareChance = 0.0;
    int nHasRarities = 0;
    if (sType == "Melee" || sType == "Range" || sType == "Weapon")
    {
        nHasRarities = 1;
        fCommonChance = IntToFloat(WEAPON_COMMON_CHANCE)/100.0;
        fUncommonChance = IntToFloat(WEAPON_UNCOMMON_CHANCE)/100.0;
        fRareChance = IntToFloat(WEAPON_RARE_CHANCE)/100.0;
    }
    else if (sType == "Armor" || sType == "Apparel")
    {
        nHasRarities = 1;
        fCommonChance = IntToFloat(APPAREL_ARMOR_COMMON_CHANCE)/100.0;
        fUncommonChance = IntToFloat(APPAREL_ARMOR_UNCOMMON_CHANCE)/100.0;
        fRareChance = IntToFloat(APPAREL_ARMOR_RARE_CHANCE)/100.0;
    }
    float fUniqueChance = IntToFloat(UNIQUE_ITEM_CHANCE)/100.0;
    if (sType == "Misc" || sType == "Apparel" || sType == "Scrolls" || sType == "Jewels")
    {
        // These do not have nonuniques
        fUniqueChance = 1.0;
    }

    int nUniqueState;
    int nRarity;
    string sTier = "T" + IntToString(nTier);

    float fTotal;

    for (nUniqueState=0; nUniqueState<=1; nUniqueState++)
    {
        string sNonUnique;
        float fChanceAtThisUniqueness;
        if (nUniqueState == 0)
        {
            sNonUnique = "NonUnique";
            fChanceAtThisUniqueness = 1.0 - fUniqueChance;
        }
        else
        {
            sNonUnique = "";
            fChanceAtThisUniqueness = fUniqueChance;
        }
        for (nRarity=0; nRarity<=2; nRarity++)
        {
            string sRarity;
            float fChanceAtThisRarity = 0.0;
            if (!nHasRarities)
            {
                sRarity = "";
                fChanceAtThisRarity = 1.0;
            }
            else
            {

                if (nRarity == 0)
                {
                    sRarity = "Common";
                    fChanceAtThisRarity = fCommonChance;
                }
                else if (nRarity == 1)
                {
                    sRarity = "Uncommon";
                    fChanceAtThisRarity = fUncommonChance;
                }
                else
                {
                    sRarity = "Rare";
                    fChanceAtThisRarity = fRareChance;
                }
            }

            object oChest = GetObjectByTag("_"+sType+sRarity+sTier+sNonUnique);
            if (!GetIsObjectValid(oChest))
            {
                oChest = GetObjectByTag("_"+sType+sRarity+sTier+"NonUnique");
            }
            int nRealObjCount = 0;
            int nGoldTotal = 0;
            if (GetIsObjectValid(oChest))
            {
                object oTest = GetFirstItemInInventory(oChest);
                while (GetIsObjectValid(oTest))
                {
                    int nBaseType = GetBaseItemType(oTest);
                    if (nBaseType == BASE_ITEM_THROWINGAXE || nBaseType == BASE_ITEM_DART || nBaseType == BASE_ITEM_SHURIKEN || nBaseType == BASE_ITEM_ARROW || nBaseType == BASE_ITEM_BULLET || nBaseType == BASE_ITEM_BOLT)
                    {
                        int nOneItemGold = GetIdentifiedItemCost(oTest)/GetItemStackSize(oTest);
                        // generation sets stack size to d45 = expected 23: (n+1)/2
                        float fStackMultiplier = 23.0/IntToFloat(GetItemStackSize(oTest));
                        int nCost = FloatToInt(IntToFloat(GetIdentifiedItemCost(oTest)) * fStackMultiplier);
                        nGoldTotal += nCost;
                    }
                    else
                    {
                        nGoldTotal += GetIdentifiedItemCost(oTest);
                    }
                    nRealObjCount++;
                    oTest = GetNextItemInInventory(oChest);
                }
            }
            else
            {
                // Avoid division by 0
                nRealObjCount = 1;
            }

            float fAverageForThisChest = IntToFloat(nGoldTotal)/IntToFloat(nRealObjCount);
            float fContribution = fAverageForThisChest * fChanceAtThisRarity * fChanceAtThisUniqueness;
            fTotal += fContribution;

            // If only one rarity, we don't need to bother with the rarity looping
            if (!nHasRarities)
            {
                break;
            }
        }
    }

    // Misc might be replaced by jewels
    if (sType == "Misc")
    {
        float fJewelChance = IntToFloat(MISC_CHANCE_TO_BE_JEWEL)/100.0;
        float fMiscChance = 1.0 - fJewelChance;
        fTotal = (fMiscChance * fTotal) + (fJewelChance * GetAverageLootValueOfItem(nTier, "Jewels"));
    }

    if (fTotal == 0.0)
    {
        // Hack to avoid doing checking the container every time the value of an item from this chest is called for
        fTotal = 0.01;
    }

    SetLocalFloat(GetModule(), sVar, fTotal);
    SendDebugMessage("Average value of t" + IntToString(nTier) + " " + sType + " = " + FloatToString(fTotal), TRUE);
    return fTotal;
}

void LootDebugOutput()
{
    int nTier;
    float fGoldTotal = 0.0;
    for (nTier=1; nTier<=5; nTier++)
    {
        string sVar = LOOT_DEBUG_OUTPUT + IntToString(nTier);
        fGoldTotal += GetLocalFloat(GetModule(), sVar);
        SendDebugMessage("Expected value of tier " + IntToString(nTier) + " items: " + FloatToString(GetLocalFloat(GetModule(), sVar)), TRUE);
        sVar = sVar + "_numitems";
        SendDebugMessage("Expected number of tier " + IntToString(nTier) + " items: " + FloatToString(GetLocalFloat(GetModule(), sVar)), TRUE);
    }
    float fRawGold = GetLocalFloat(GetModule(), LOOT_DEBUG_GOLD);
    SendDebugMessage("Expected raw gold: " + FloatToString(fRawGold), TRUE);
    SendDebugMessage("Total item value: " + FloatToString(fGoldTotal), TRUE);
}

// Reset the loot tracker.
void ResetLootDebug()
{
    int nTier;
    for (nTier=1; nTier<=5; nTier++)
    {
        string sVar = LOOT_DEBUG_OUTPUT + IntToString(nTier);
        SetLocalFloat(GetModule(), sVar, 0.0);
        sVar = sVar + "_numitems";
        SetLocalFloat(GetModule(), sVar, 0.0);
    }
    SetLocalFloat(GetModule(), LOOT_DEBUG_GOLD, 0.0);
    DeleteLocalObject(GetModule(), LOOT_DEBUG_AREA);
}


//void main() {}
