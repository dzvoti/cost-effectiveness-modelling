#' Calculate Baseline Nutrient Inadequacy (AFE Method)
#'
#' This function calculates the baseline inadequacy of nutrients for different administrative groups using the Adequate Food Energy (AFE) Method.
#'
#' @param householdConsumptionDf A dataframe containing household consumption data. Must contain columns: "householdId", "amountConsumedInG", "memberCount".
#' @param householdDetailsDf A dataframe containing household details. Must contain column: "householdId".
#' @param nctListDf A dataframe containing nutrient composition tables. Must contain columns: "nutrient", "foodId".
#' @param intakeThresholdsDf A dataframe containing intake thresholds for nutrients. Must contain columns: "nutrient", "CND".
#' @param aggregationGroup A character vector of administrative groups to aggregate the data. Must not be empty. Defaults to c("admin0Name", "admin1Name").
#' @param MNList A character vector of nutrients to be included in the analysis. If empty, defaults to a comprehensive list of nutrients.
#'
#' @return A dataframe with the baseline inadequacy of nutrients for the specified administrative groups.
#' @export
#'
#' @examples
#' \dontrun{
#' calculateBaselineInadequacyAfe(
#'     householdConsumptionDf = householdConsumption,
#'     householdDetailsDf = householdDetails,
#'     nctListDf = nctList,
#'     intakeThresholdsDf = intakeThresholds,
#'     aggregationGroup = c("admin0Name", "admin1Name"),
#'     MNList = c("Ca", "Carbohydrates")
#' )
#' }
calculate_pre_and_post_lsff_summaries_afe <- function(
    householdConsumptionDf = householdConsumption,
    householdDetailsDf = householdDetails,
    nctListDf = nctList,
    intakeThresholdsDf = intakeThresholds,
    aggregationGroup = c("admin0Name", "admin1Name"),
    fortifiableFoodItemsDf = createFortifiableFoodItemsTable(),
    foodVehicleName = "wheat flour",
    years = c(2021:2024),
    # MNList = c("Ca", "Carbohydrates", "Cu", "Energy", "Fat", "Fe", "Fibre", "I", "IP6", "Mg", "Protein", "Se", "Zn", "Ash", "B6", "B2", "D", "N", "K", "P", "Moisture", "Cholesterol", "E", "Na", "A", "C", "B12", "B1", "B3", "B9", "B5", "B7", "Mn"),
    MNList = "A") {
    # Define required columns
    requiredConsumptionCols <- c("householdId", "amountConsumedInG")
    requiredDetailsCols <- c("householdId", "memberCount")
    requiredNctCols <- c("micronutrientId")
    requiredIntakeCols <- c("nutrient", "CND")

    # Check if MNList is a character vector
    if (!is.character(MNList)) {
        stop("MNList must be a character vector e.g. c('A', 'Ca')")
    }

    # Check if aggregationGroup is a character vector
    if (!is.character(aggregationGroup)) {
        stop("aggregationGroup must be a character vector e.g. c('admin0Name', 'admin1Name')")
    }

    # Check if MNList and aggregationGroup are not empty
    if (length(aggregationGroup) == 0) {
        stop("aggregationGroup cannot be empty")
    }

    # Check if input dataframes have required columns
    if (!all(requiredConsumptionCols %in% names(householdConsumptionDf))) {
        stop(paste("householdConsumptionDf must contain the following columns:", paste(requiredConsumptionCols, collapse = ", ")))
    }

    if (!all(requiredDetailsCols %in% names(householdDetailsDf))) {
        stop(paste("householdDetailsDf must contain the following column:", paste(requiredDetailsCols, collapse = ", ")))
    }

    if (!all(requiredNctCols %in% names(nctListDf))) {
        stop(paste("nctListDf must contain the following columns:", paste(requiredNctCols, collapse = ", ")))
    }

    if (!all(requiredIntakeCols %in% names(intakeThresholdsDf))) {
        stop(paste("intakeThresholdsDf must contain the following columns:", paste(requiredIntakeCols, collapse = ", ")))
    }

    # Use the createMasterNct function to create a master NCT
    masterNCT <- effectivenessCalculations::createMasterNct(nctList)

    # Filter the fortifiable food items to get the food vehicle
    fortifiableFoodVehicle <- fortifiableFoodItemsDf |>
        dplyr::filter(food_vehicle_name == foodVehicleName)

    ## Create a wider format for the intakeThresholds
    earThreshholds <- intakeThresholdsDf |>
        dplyr::select(nutrient, ear) |>
        # Remove rows where ear is NA
        dplyr::filter(!is.na(ear)) |>
        # Leave thresholds for the nutrients in the MNList
        dplyr::filter(nutrient %in% MNList) |>
        tidyr::pivot_wider(names_from = nutrient, values_from = ear) |>
        # Convert all columns to numeric
        dplyr::mutate_all(as.numeric) |>
        # Add a suffix of "ear" to the column names
        dplyr::rename_with(~ paste0(., "SupplyEarThreshold"), dplyr::everything())

    # Process the consumption data
    # Load the consumption data
    enrichedHouseholdConsumption <- householdConsumptionDf |>
        # Not necessary by its a personal preference
        tibble::as_tibble() |>
        # Join the household details to the consumption data (Joining columns with the same name)
        dplyr::left_join(householdDetailsDf) |>
        # Join the master NCT to the consumption data
        dplyr::left_join(masterNCT) |>
        dplyr::left_join(fortifiableFoodVehicle, by = c("foodGenusId" = "food_genus_id")) |>
        # Convert all columns needed for calculations to numeric
        dplyr::mutate_at(c("amountConsumedInG", "afeFactor", "fortifiable_portion", MNList), as.numeric) |>
        dplyr::mutate(dplyr::across(MNList, ~ . / afeFactor), amountConsumedInGAfe = amountConsumedInG / afeFactor) |>
        dplyr::bind_cols(earThreshholds)


    # Calculate HH count summaries
    HHCountSummaries <- enrichedHouseholdConsumption |>
        dplyr::group_by(dplyr::across(dplyr::all_of(aggregationGroup))) |>
        dplyr::distinct(householdId) |>
        dplyr::summarise(householdsCount = dplyr::n())

    # Fortification vehicle reach summaries
    fortificationVehicleReach <- enrichedHouseholdConsumption |>
        dplyr::group_by(dplyr::across(dplyr::all_of(aggregationGroup))) |>
        dplyr::filter(!is.na(food_vehicle_name)) |>
        dplyr::distinct(householdId) |>
        dplyr::summarize(fortification_vehicle_reach_hh_count = dplyr::n())

    # Mean and median fortification vehicle amounts consumed
    fortificationVehicleAmountsConsumedAfe <- enrichedHouseholdConsumption |>
        dplyr::filter(!is.na(food_vehicle_name)) |>
        dplyr::group_by(householdId) |>
        dplyr::summarize(median_fortification_vehicle_amountConsumedInGAfe = median(amountConsumedInGAfe, na.rm = TRUE), mean_fortification_vehicle_amountConsumedInGAfe = mean(amountConsumedInGAfe, na.rm = TRUE)) |>
        dplyr::left_join(householdDetailsDf) |>
        dplyr::group_by(dplyr::across(dplyr::all_of(aggregationGroup))) |>
        dplyr::summarize(
            median_fortification_vehicle_amountConsumedInGAfe = median(median_fortification_vehicle_amountConsumedInGAfe, na.rm = TRUE), mean_fortification_vehicle_amountConsumedInGAfe = mean(mean_fortification_vehicle_amountConsumedInGAfe, na.rm = TRUE)
        )

    # Average daily consumption per AFE
    amountConsumedPerDayAfe <- enrichedHouseholdConsumption |>
        dplyr::group_by(householdId) |>
        dplyr::summarize(
            dailyAmountConsumedPerAfeInG = sum(amountConsumedInG / 100 * afeFactor, na.rm = TRUE)
        ) |>
        dplyr::left_join(householdDetailsDf) |>
        dplyr::group_by(dplyr::across(dplyr::all_of(aggregationGroup))) |>
        dplyr::summarize(
            meanDailyAmountConsumedPerAfeInG = mean(dailyAmountConsumedPerAfeInG, na.rm = TRUE),
            medianDailyAmountConsumedPerAfeInG = median(dailyAmountConsumedPerAfeInG, na.rm = TRUE)
        )

    # Amount consumed containing fortificant
    amountConsumedContainingFortificant <- enrichedHouseholdConsumption |>
        dplyr::group_by(householdId) |>
        dplyr::filter(!is.na(food_vehicle_name)) |>
        dplyr::summarize(
            dailyAmountConsumedPerAfeInG = sum(amountConsumedInG / afeFactor, na.rm = TRUE)
        ) |>
        dplyr::left_join(householdDetailsDf) |>
        dplyr::group_by(dplyr::across(dplyr::all_of(aggregationGroup))) |>
        dplyr::summarize(
            meanDailyamountConsumedContainingFortificantInG = mean(dailyAmountConsumedPerAfeInG, na.rm = TRUE),
            medianDailyAmountConsumedContainingFortificantInG = median(dailyAmountConsumedPerAfeInG, na.rm = TRUE)
        )

    # Merge the summaries
    initialSummaries <- HHCountSummaries |>
        dplyr::left_join(fortificationVehicleReach) |>
        dplyr::left_join(amountConsumedPerDayAfe) |>
        dplyr::left_join(amountConsumedContainingFortificant) |>
        dplyr::left_join(fortificationVehicleAmountsConsumedAfe)



    for (nutrient in MNList) {
        enrichedHouseholdConsumption[paste0(nutrient, "_BaseSupply")] <- enrichedHouseholdConsumption[nutrient] / 100 * enrichedHouseholdConsumption["amountConsumedInG"]

        for (year in years) {
            # Calculate the supply of the nutrient with LSFF per food item
            enrichedHouseholdConsumption[paste0(nutrient, "_", year, "_LSFFSupply")] <- enrichedHouseholdConsumption[paste0(nutrient, "_BaseSupply")] * yearAverageFortificationLevel(fortification_vehicle = foodVehicleName, Year = year, MN = nutrient) * enrichedHouseholdConsumption["fortifiable_portion"] / 100
        }
    }

    # aggregate nutrient supplies by household
    nutrientSupply <- enrichedHouseholdConsumption |>
        dplyr::group_by(householdId) |>
        dplyr::summarize(
            dplyr::across(dplyr::ends_with("_BaseSupply"), ~ sum(.x, na.rm = TRUE), .names = "{.col}"),
            dplyr::across(dplyr::ends_with("_LSFFSupply"), ~ sum(.x, na.rm = TRUE), .names = "{.col}")
        )

    # Calculate mean and median nutrient supplies
    # TODO: These were checked and are consistent with the maps tool.
    medianNutrientSupplySummaries <- nutrientSupply |>
        dplyr::left_join(householdDetailsDf) |>
        dplyr::group_by(dplyr::across(dplyr::all_of(aggregationGroup))) |>
        dplyr::summarize(
            dplyr::across(dplyr::ends_with("_BaseSupply"), ~ round(mean(.x, na.rm = TRUE), 0), .names = "{.col}MeanSupply"),
            dplyr::across(dplyr::ends_with("_BaseSupply"), ~ round(median(.x, na.rm = TRUE), 0), .names = "{.col}MedianSupply")
        )

    # Add _BaseSupply and _LSFFSupply for each nutrient and year combo
    for (nutrient in MNList) {
        for (year in years) {
            nutrientSupply[paste0(nutrient, "_", year, "_BaseAndLSFFTotalSupply")] <- nutrientSupply[paste0(nutrient, "_BaseSupply")] + nutrientSupply[paste0(nutrient, "_", year, "_LSFFSupply")]
        }
    }

    # Remerge the household details
    enrichedNutrientSupply <- nutrientSupply |>
        # corce afefactor to numeric
        dplyr::left_join(householdDetailsDf) |>
        dplyr::bind_cols(earThreshholds)


    # Create adequacy columns for each Baseline and LSFF nutrient supply
    # NOTE: This code is not pretty and can be improved. It works for now
    for (nutrient in MNList) {
        if (!is.na(effectivenessCalculations::getMnThresholds(intakeThresholds, nutrient, "ear"))) {
            enrichedNutrientSupply[paste0(nutrient, "_base_supply_ear_inadequacy")] <- ifelse(enrichedNutrientSupply[paste0(nutrient, "_BaseSupply")] >= effectivenessCalculations::getMnThresholds(intakeThresholdsDf, nutrient, "ear"), 0, 1)
        }
        for (year in years) {
            if (!is.na(effectivenessCalculations::getMnThresholds(intakeThresholds, nutrient, "ear"))) {
                enrichedNutrientSupply[paste0(nutrient, "_", year, "_base_and_lsff_ear_inadequacy")] <- ifelse(enrichedNutrientSupply[paste0(nutrient, "_", year, "_BaseAndLSFFTotalSupply")] >= effectivenessCalculations::getMnThresholds(intakeThresholdsDf, nutrient, "ear"), 0, 1)
            }
        }
    }

    # Check if the intake is above the Upper Limit
    for (nutrient in MNList) {
        if (!is.na(effectivenessCalculations::getMnThresholds(intakeThresholds, nutrient, "ul"))) {
            enrichedNutrientSupply[paste0(nutrient, "_base_ul_exceedance")] <- ifelse(enrichedNutrientSupply[paste0(nutrient, "_BaseSupply")] > effectivenessCalculations::getMnThresholds(intakeThresholdsDf, nutrient, "ul"), 1, 0)
        }
        for (year in years) {
            if (!is.na(effectivenessCalculations::getMnThresholds(intakeThresholds, nutrient, "ul"))) {
                enrichedNutrientSupply[paste0(nutrient, "_", year, "_base_and_lsff_ul_exceedance")] <- ifelse(enrichedNutrientSupply[paste0(nutrient, "_", year, "_BaseAndLSFFTotalSupply")] > effectivenessCalculations::getMnThresholds(intakeThresholdsDf, nutrient, "ul"), 1, 0)
            }
        }
    }

    # Create adequacy summaries
    inadequacySummarries <- enrichedNutrientSupply |>
        dplyr::left_join(householdDetailsDf) |>
        dplyr::group_by(dplyr::across(dplyr::all_of(aggregationGroup))) |>
        dplyr::summarize(
            dplyr::across(dplyr::ends_with("_base_supply_ear_inadequacy"), ~ sum(.x, na.rm = TRUE), .names = "{.col}_count"),
            dplyr::across(dplyr::ends_with("_base_ul_exceedance"), ~ sum(.x, na.rm = TRUE), .names = "{.col}_count")
        ) |>
        dplyr::left_join(initialSummaries) |>
        dplyr::mutate(dplyr::across(dplyr::ends_with("_count"), ~ round((.x * 100 / householdsCount), 2), .names = "{.col}_perc"))

    # Get the column order for the data
    columnOrder <- sort(names(inadequacySummarries))

    # Reorder the columns for better readability
    finalSummarries <- inadequacySummarries |>
        dplyr::select(dplyr::all_of(columnOrder)) |>
        dplyr::select(aggregationGroup, householdsCount, dplyr::everything())

    return(finalSummarries)
}