/* moved to modular
//Check if the limb is dismemberable
/obj/item/bodypart/proc/can_dismember(obj/item/I)
	if(dismemberable)
		return TRUE

//Dismember a limb
/obj/item/bodypart/proc/dismember(dam_type = BRUTE, silent = FALSE, destroy = FALSE)
	if(!owner)
		return FALSE
	var/mob/living/carbon/C = owner
	if(!dismemberable)
		return FALSE
	if(C.status_flags & GODMODE)
		return FALSE
	if(HAS_TRAIT(C, TRAIT_NODISMEMBER))
		return FALSE
	var/obj/item/bodypart/affecting = C.get_bodypart(BODY_ZONE_CHEST)
	affecting.receive_damage(clamp(brute_dam/2 * affecting.body_damage_coeff, 15, 50), clamp(burn_dam/2 * affecting.body_damage_coeff, 0, 50), wound_bonus=CANT_WOUND) //Damage the chest based on limb's existing damage //skyrat edit
	if(!silent)
		C.visible_message("<span class='danger'><B>[C]'s [src.name] has been violently dismembered!</B></span>")
	if(body_zone != BODY_ZONE_HEAD)
		C.emote("scream")
	playsound(get_turf(C), 'modular_skyrat/sound/effects/dismember.ogg', 80, TRUE) //skyrat edit
	SEND_SIGNAL(C, COMSIG_ADD_MOOD_EVENT, "dismembered", /datum/mood_event/dismembered)
	drop_limb(dismembered = TRUE, destroyed = (dam_type == BURN ? TRUE : destroy))
	C.update_equipment_speed_mods() // Update in case speed affecting item unequipped by dismemberment

	C.bleed(40)

	if(QDELETED(src)) //Could have dropped into lava/explosion/chasm/whatever
		return TRUE
	if(dam_type == BURN)
		burn()
		return TRUE
	add_mob_blood(C)
	C.bleed(rand(20, 40))
	var/direction = pick(GLOB.cardinals)
	var/t_range = rand(2,max(throw_range/2, 2))
	var/turf/target_turf = get_turf(src)
	for(var/i in 1 to t_range-1)
		var/turf/new_turf = get_step(target_turf, direction)
		if(!new_turf)
			break
		target_turf = new_turf
		if(new_turf.density)
			break
	throw_at(target_turf, throw_range, throw_speed)
	return TRUE

//Disembowel a limb
/obj/item/bodypart/proc/disembowel(dam_type = BRUTE, silent = FALSE)
	if(!owner)
		return FALSE
	var/mob/living/carbon/C = owner
	if(!disembowable)
		return FALSE
	if(HAS_TRAIT(C, TRAIT_NODISMEMBER))
		return FALSE
	if(HAS_TRAIT(C, TRAIT_NOGUT)) //Just for not allowing disembowelment
		return FALSE
	. = list()
	var/organ_spilled = 0
	var/turf/T = get_turf(C)
	for(var/X in C.internal_organs)
		var/obj/item/organ/O = X
		var/org_zone = check_zone(O.zone)
		if(org_zone != body_zone)
			continue
		O.Remove()
		O.forceMove(T)
		organ_spilled = 1
		. += X
	
	if(cavity_item)
		cavity_item.forceMove(T)
		. += cavity_item
		cavity_item = null
		organ_spilled = 1

	if(organ_spilled)
		playsound(get_turf(C), 'sound/misc/splort.ogg', 80, 1)
		C.bleed(50)
		C.visible_message("<span class='danger'><B>[C]'s [parse_zone(body_zone)] organs spill out onto the floor!</B></span>")
		return TRUE
	
	return FALSE

/obj/item/bodypart/head/dismember(dam_type = BRUTE, silent = FALSE)
	if(HAS_TRAIT(owner, TRAIT_NODECAP) || HAS_TRAIT(owner, TRAIT_NODISMEMBER))
		return FALSE
	..()

//limb removal. The "special" argument is used for swapping a limb with a new one without the effects of losing a limb kicking in.
/obj/item/bodypart/proc/drop_limb(special, ignore_children = FALSE, dismembered = FALSE, destroyed = FALSE) //skyrat edit
	if(!owner)
		return
	var/atom/Tsec = owner.drop_location()
	var/mob/living/carbon/C = owner
	SEND_SIGNAL(C, COMSIG_CARBON_REMOVE_LIMB, src, dismembered) //skyrat edit
	update_limb(1)
	C.bodyparts -= src

	if(held_index)
		C.dropItemToGround(owner.get_item_for_held_index(held_index), 1)
		C.hand_bodyparts[held_index] = null
	//skyrat edit
	for(var/thing in scars)
		var/datum/scar/S = thing
		if(istype(S))
			S.victim = null
			LAZYREMOVE(owner.all_scars, S)

	for(var/thing in wounds)
		var/datum/wound/W = thing
		W.remove_wound(TRUE)
	
	if(dismembered && dismember_bodyzone)
		var/obj/item/bodypart/BP = owner.get_bodypart(dismember_bodyzone)
		if(istype(BP))
			var/datum/wound/lost
			if(is_organic_limb())
				lost = new /datum/wound/slash/loss()
			else
				lost = new /datum/wound/mechanical/slash/loss()
			lost.name = "[lost.name] [lowertext(name)] stump"
			lost.fake_limb = "[name]"
			lost.fake_body_zone = body_zone
			lost.desc = "Patient's [lowertext(name)] has been violently dismembered from [owner.p_their(FALSE)] [parse_zone(dismember_bodyzone)], leaving only a severely damaged stump in it's place."
			lost.examine_desc = "has been violently severed from their [parse_zone(dismember_bodyzone)]"
			lost.apply_wound(BP, TRUE)
	//
	owner = null
	//skyrat edit
	if(!ignore_children)
		for(var/BP in children_zones)
			var/obj/item/bodypart/thing = C.get_bodypart(BP)
			if(thing)
				thing.drop_limb(special, ignore_children, dismembered, destroyed)
				thing.forceMove(src)
		C.updatehealth()
	//
	for(var/X in C.surgeries) //if we had an ongoing surgery on that limb, we stop it.
		var/datum/surgery/S = X
		if(S.operated_bodypart == src)
			C.surgeries -= S
			qdel(S)
			break

	for(var/obj/item/I in embedded_objects)
		embedded_objects -= I
		I.forceMove(src)
		I.unembedded()
	if(!C.has_embedded_objects())
		C.clear_alert("embeddedobject")
		SEND_SIGNAL(C, COMSIG_CLEAR_MOOD_EVENT, "embedded")

	if(!special)
		if(C.dna)
			for(var/X in C.dna.mutations) //some mutations require having specific limbs to be kept.
				var/datum/mutation/human/MT = X
				if(MT.limb_req && MT.limb_req == body_zone)
					C.dna.force_lose(MT)

		for(var/X in C.internal_organs) //internal organs inside the dismembered limb are dropped.
			var/obj/item/organ/O = X
			var/org_zone = check_zone(O.zone)
			if(org_zone != body_zone)
				continue
			O.transfer_to_limb(src, C)

	update_icon_dropped()
	if(destroyed)
		for(var/obj/item/organ/O in src)
			O.setOrganDamage(max(O.damage, O.maxHealth * 0.9))
			O.forceMove(get_turf(src))
	C.update_health_hud() //update the healthdoll
	C.update_body()
	C.update_hair()
	C.update_mobility()

	if(!Tsec || destroyed)	// Tsec = null happens when a "dummy human" used for rendering icons on prefs screen gets its limbs replaced.
		qdel(src)
		return

	if(is_pseudopart)
		drop_organs(C)	//Psuedoparts shouldn't have organs, but just in case
		qdel(src)
		return

	forceMove(Tsec)
/**
  * get_mangled_state() is relevant for flesh and bone bodyparts, and returns whether this bodypart has mangled skin, mangled bone, or both (or neither i guess)
  *
  * Dismemberment for flesh and bone requires the victim to have the skin on their bodypart destroyed (either a critical cut or piercing wound), and at least a hairline fracture
  * (severe bone), at which point we can start rolling for dismembering. The attack must also deal at least 10 damage, and must be a brute attack of some kind (sorry for now, cakehat, maybe later)
  *
  * Returns: BODYPART_MANGLED_NONE if we're fine, BODYPART_MANGLED_SKIN if our skin is broken, BODYPART_MANGLED_BONE if our bone is broken, or BODYPART_MANGLED_BOTH if both are broken and we're up for dismembering
  */
/obj/item/bodypart/proc/get_mangled_state()
	var/mangled_state = BODYPART_MANGLED_NONE
	var/required_bone_severity = WOUND_SEVERITY_SEVERE

	if(owner && owner.get_biological_state() == BIO_JUST_BONE && !HAS_TRAIT(owner, TRAIT_EASYDISMEMBER))
		required_bone_severity = WOUND_SEVERITY_CRITICAL

	// we can (generally) only have one wound per type, but remember there's multiple types
	for(var/i in wounds)
		var/datum/wound/W = i
		if(istype(W, /datum/wound/blunt) && W.severity >= required_bone_severity)
			mangled_state |= BODYPART_MANGLED_BONE
		if((istype(W, /datum/wound/slash) || istype(W, /datum/wound/pierce)) && W.severity >= WOUND_SEVERITY_CRITICAL)
			mangled_state |= BODYPART_MANGLED_MUSCLE
		if((istype(W, /datum/wound/slash) || istype(W, /datum/wound/pierce)) && W.severity >= WOUND_SEVERITY_MODERATE)
			mangled_state |= BODYPART_MANGLED_SKIN

	return mangled_state

/**
  * try_dismember() is used, once we've confirmed that a flesh and bone bodypart has both the skin, muscle and bone mangled, to actually roll for it
  *
  * Mangling is described in the above proc, [/obj/item/bodypart/proc/get_mangled_state()]. This simply makes the roll for whether we actually dismember or not
  * using how damaged the limb already is, and how much damage this blow was for. If we have a critical bone wound instead of just a severe, we add +10% to the roll.
  * Lastly, we choose which kind of dismember we want based on the wounding type we hit with
  *
  * Arguments:
  * * wounding_type: Either WOUND_BLUNT, WOUND_SLASH, or WOUND_PIERCE, basically only matters for the dismember message
  * * wounding_dmg: The damage of the strike that prompted this roll, higher damage = higher chance
  * * wound_bonus: Not actually used right now, but maybe someday
  * * bare_wound_bonus: ditto above
  */
/obj/item/bodypart/proc/try_dismember(wounding_type, wounding_dmg, wound_bonus, bare_wound_bonus)
	if(!can_dismember() || !dismemberable || (wounding_dmg < DISMEMBER_MINIMUM_DAMAGE))
		return FALSE
	var/base_chance = wounding_dmg + ((get_damage() / max_damage) * 50) // how much damage we dealt with this blow, + 50% of the damage percentage we already had on this bodypart
	var/biotype = owner.get_biological_state()
	for(var/i in wounds)
		var/datum/wound/W = i
		if(((istype(W, /datum/wound/blunt/critical) || istype(W, /datum/wound/mechanical/blunt/critical)) && (biotype & BIO_JUST_BONE))) // we only require a severe bone break, but if there's a critical bone break, we'll add 10% more
			base_chance += 10
			break
		else if((istype(W, /datum/wound/slash/critical) || istype(W, /datum/wound/pierce/critical) || istype(W, /datum/wound/mechanical/slash/critical || istype(W, /datum/wound/mechanical/pierce/critical))) && (biotype & BIO_JUST_FLESH))
			base_chance += 10
			break


	if(!prob(base_chance))
		return

	dismember_wound(wounding_type)

	return TRUE

/obj/item/bodypart/proc/dismember_wound(wounding_type)
	var/datum/wound/loss/dismembering = new
	dismembering.apply_dismember(src, wounding_type)

/obj/item/bodypart/proc/try_disembowel(wounding_type, wounding_dmg, wound_bonus, bare_wound_bonus)
	if(!can_dismember() || !disembowable || (wounding_dmg < DISMEMBER_MINIMUM_DAMAGE))
		return FALSE
	var/base_chance = wounding_dmg + ((get_damage() / max_damage) * 50) // how much damage we dealt with this blow, + 50% of the damage percentage we already had on this bodypart
	var/biotype = owner.get_biological_state()
	for(var/i in wounds)
		var/datum/wound/W = i
		if(istype(W, /datum/wound/slash/critical/incision) && (biotype & BIO_JUST_FLESH)) // incisions make you very vulnerable to disembowelment
			base_chance += 20
			break
		else if((istype(W, /datum/wound/slash/critical) || istype(W, /datum/wound/pierce/critical) || istype(W, /datum/wound/mechanical/slash/critical || istype(W, /datum/wound/mechanical/pierce/critical))) && (biotype & BIO_JUST_FLESH)) // we only require a severe slash, but if we have an avulsion, it's easier for an organ to fall off
			base_chance += 10
			break
		else if((istype(W, /datum/wound/blunt/critical) || istype(W, /datum/wound/mechanical/blunt/critical)) && (biotype & BIO_JUST_BONE)) // skeletons need to be disemboweled too because they have "organs"...?
			base_chance += 10
			break


	if(!prob(base_chance))
		return

	switch(wounding_type)
		if(WOUND_BLUNT)
			wounding_type = BRUTE
		if(WOUND_SLASH)
			wounding_type = BRUTE
		if(WOUND_PIERCE)
			wounding_type = BRUTE
		if(WOUND_BURN)
			wounding_type = BURN

	if(disembowel(wounding_type, FALSE))
		return TRUE

//when a limb is dropped, the internal organs are removed from the mob and put into the limb
/obj/item/organ/proc/transfer_to_limb(obj/item/bodypart/LB, mob/living/carbon/C)
	Remove()
	forceMove(LB)

/obj/item/organ/brain/transfer_to_limb(obj/item/bodypart/head/LB, mob/living/carbon/human/C)
	Remove()	//Changeling brain concerns are now handled in Remove
	forceMove(LB)
	LB.brain = src
	if(brainmob)
		LB.brainmob = brainmob
		brainmob = null
		LB.brainmob.forceMove(LB)
		LB.brainmob.stat = DEAD

/obj/item/organ/eyes/transfer_to_limb(obj/item/bodypart/head/LB, mob/living/carbon/human/C)
	LB.eyes = src
	..()

/obj/item/bodypart/chest/drop_limb(special, ignore_children = FALSE, dismembered = FALSE, destroyed = FALSE)
	if(special)
		..()

/obj/item/bodypart/r_hand/drop_limb(special, ignore_children = FALSE, dismembered = FALSE, destroyed = FALSE)
	var/mob/living/carbon/C = owner
	..()
	if(C && !special)
		if(C.handcuffed)
			C.handcuffed.forceMove(drop_location())
			C.handcuffed.dropped(C)
			C.handcuffed = null
			C.update_handcuffed()
		if(C.hud_used)
			var/obj/screen/inventory/hand/R = C.hud_used.hand_slots["[held_index]"]
			if(R)
				R.update_icon()
		if(C.gloves)
			C.dropItemToGround(C.gloves, TRUE)
		C.update_inv_gloves() //to remove the bloody hands overlay

/obj/item/bodypart/l_hand/drop_limb(special, ignore_children = FALSE, dismembered = FALSE, destroyed = FALSE)
	var/mob/living/carbon/C = owner
	..()
	if(C && !special)
		if(C.handcuffed)
			C.handcuffed.forceMove(drop_location())
			C.handcuffed.dropped(C)
			C.handcuffed = null
			C.update_handcuffed()
		if(C.hud_used)
			var/obj/screen/inventory/hand/L = C.hud_used.hand_slots["[held_index]"]
			if(L)
				L.update_icon()
		if(C.gloves)
			C.dropItemToGround(C.gloves, TRUE)
		C.update_inv_gloves() //to remove the bloody hands overlay


/obj/item/bodypart/r_foot/drop_limb(special, ignore_children = FALSE, dismembered = FALSE, destroyed = FALSE)
	if(owner && !special)
		if(owner.legcuffed)
			owner.legcuffed.forceMove(owner.drop_location()) //At this point bodypart is still in nullspace
			owner.legcuffed.dropped(owner)
			owner.legcuffed = null
			owner.update_inv_legcuffed()
		if(owner.shoes)
			owner.dropItemToGround(owner.shoes, TRUE)
	..()

/obj/item/bodypart/l_foot/drop_limb(special, ignore_children = FALSE, dismembered = FALSE, destroyed = FALSE) //copypasta
	if(owner && !special)
		if(owner.legcuffed)
			owner.legcuffed.forceMove(owner.drop_location())
			owner.legcuffed.dropped(owner)
			owner.legcuffed = null
			owner.update_inv_legcuffed()
		if(owner.shoes)
			owner.dropItemToGround(owner.shoes, TRUE)
	..()

/obj/item/bodypart/head/drop_limb(special, ignore_children = FALSE, dismembered = FALSE, destroyed = FALSE)
	if(!special)
		//Drop all worn head items
		for(var/X in list(owner.glasses, owner.ears, owner.wear_mask, owner.head))
			var/obj/item/I = X
			owner.dropItemToGround(I, TRUE)

	owner.wash_cream() //clean creampie overlay

	//Handle dental implants
	for(var/datum/action/item_action/hands_free/activate_pill/AP in owner.actions)
		AP.Remove(owner)
		var/obj/pill = AP.target
		if(pill)
			pill.forceMove(src)

	//Make sure de-zombification happens before organ removal instead of during it
	var/obj/item/organ/zombie_infection/ooze = owner.getorganslot(ORGAN_SLOT_ZOMBIE)
	if(istype(ooze))
		ooze.transfer_to_limb(src, owner)

	name = "[owner.real_name]'s head"
	..()

//Attach a limb to a human and drop any existing limb of that type.
/obj/item/bodypart/proc/replace_limb(mob/living/carbon/C, special)
	if(!istype(C))
		return
	var/obj/item/bodypart/O = C.get_bodypart(body_zone)
	if(O)
		O.drop_limb(1)
	attach_limb(C, special)

/obj/item/bodypart/head/replace_limb(mob/living/carbon/C, special)
	if(!istype(C))
		return
	var/obj/item/bodypart/head/O = C.get_bodypart(body_zone)
	if(O)
		if(!special)
			return
		else
			O.drop_limb(1)
	attach_limb(C, special)

/obj/item/bodypart/proc/attach_limb(mob/living/carbon/C, special, ignore_parent_restriction = FALSE) //skyrat edit
	//skyrat edit
	if(SEND_SIGNAL(C, COMSIG_CARBON_ATTACH_LIMB, src, special) & COMPONENT_NO_ATTACH)
		return FALSE
	if(!ignore_parent_restriction && !C.get_bodypart(parent_bodyzone))
		return FALSE
	. = TRUE
	//
	moveToNullspace()
	owner = C
	C.bodyparts += src
	if(held_index)
		if(held_index > C.hand_bodyparts.len)
			C.hand_bodyparts.len = held_index
		C.hand_bodyparts[held_index] = src
		if(C.dna.species.mutanthands && !is_pseudopart)
			C.put_in_hand(new C.dna.species.mutanthands(), held_index)
		if(C.hud_used)
			var/obj/screen/inventory/hand/hand = C.hud_used.hand_slots["[held_index]"]
			if(hand)
				hand.update_icon()
		C.update_inv_gloves()

	if(special) //non conventional limb attachment
		for(var/X in C.surgeries) //if we had an ongoing surgery to attach a new limb, we stop it.
			var/datum/surgery/S = X
			var/surgery_zone = check_zone(S.location)
			if(surgery_zone == body_zone)
				C.surgeries -= S
				qdel(S)
				break
	//skyrat edit
	for(var/obj/item/bodypart/BP in src) //stored limbs. in normal circumstances, this will be either nothing or just the children.
		BP.attach_limb(C, special, ignore_parent_restriction)
	var/obj/item/bodypart/parent = C.get_bodypart(parent_bodyzone)
	if(parent)
		for(var/datum/wound/woundie in parent)
			if((woundie.fake_body_zone == body_zone) && (woundie.severity == WOUND_SEVERITY_LOSS))
				woundie.remove_wound()
	//
	for(var/obj/item/organ/O in contents)
		O.Insert(C)
	//skyrat edit
	for(var/thing in scars)
		var/datum/scar/S = thing
		if(istype(S))
			S.victim = C
			LAZYADD(C.all_scars, thing)

	for(var/i in wounds)
		var/datum/wound/W = i
		W.apply_wound(src, TRUE)
	//

	update_bodypart_damage_state()
	update_disabled()

	C.updatehealth()
	C.update_body()
	C.update_hair()
	C.update_damage_overlays()
	C.update_mobility()

/obj/item/bodypart/head/attach_limb(mob/living/carbon/C, special)
	//Transfer some head appearance vars over
	if(brain)
		if(brainmob)
			brainmob.container = null //Reset brainmob head var.
			brainmob.forceMove(brain) //Throw mob into brain.
			brain.brainmob = brainmob //Set the brain to use the brainmob
			brainmob = null //Set head brainmob var to null
		brain.Insert(C) //Now insert the brain proper
		brain = null //No more brain in the head

	if(ishuman(C))
		var/mob/living/carbon/human/H = C
		H.hair_color = hair_color
		H.hair_style = hair_style
		H.facial_hair_color = facial_hair_color
		H.facial_hair_style = facial_hair_style
		H.lip_style = lip_style
		H.lip_color = lip_color
	if(real_name)
		C.real_name = real_name
	real_name = ""
	name = initial(name)

	//Handle dental implants
	for(var/obj/item/reagent_containers/pill/P in src)
		for(var/datum/action/item_action/hands_free/activate_pill/AP in P.actions)
			P.forceMove(C)
			AP.Grant(C)
			break

	..()


//Regenerates all limbs. Returns amount of limbs regenerated
/mob/living/proc/regenerate_limbs(noheal = FALSE, list/excluded_limbs = list())
	SEND_SIGNAL(src, COMSIG_LIVING_REGENERATE_LIMBS, noheal, excluded_limbs)

/mob/living/carbon/regenerate_limbs(noheal = FALSE, list/excluded_limbs = list(), ignore_parent_restriction = FALSE)
	. = ..()
	var/list/limb_list = ALL_BODYPARTS //skyrat edit
	if(excluded_limbs.len)
		limb_list -= excluded_limbs
	for(var/Z in limb_list)
		. += regenerate_limb(Z, noheal, ignore_parent_restriction) //skyrat edit

/mob/living/proc/regenerate_limb(limb_zone, noheal, ignore_parent_restriction) //skyrat edit
	return

/mob/living/carbon/regenerate_limb(limb_zone, noheal, ignore_parent_restriction) //skyrat edit
	var/obj/item/bodypart/L
	if(get_bodypart(limb_zone))
		return 0
	L = newBodyPart(limb_zone, 0, 0)
	if(L)
		if(!noheal)
			L.brute_dam = 0
			L.burn_dam = 0
			L.brutestate = 0
			L.burnstate = 0

		L.attach_limb(src, 1, ignore_parent_restriction) //skyrat edit
		var/datum/scar/S = new
		var/datum/wound/loss/phantom_loss = new // stolen valor, really
		S.generate(L, phantom_loss)
		QDEL_NULL(phantom_loss)
		return 1
*/
