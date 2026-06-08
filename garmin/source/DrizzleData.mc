module DrizzleData {

    const RADAR_BASE = "https://sirocco.accuweather.com/nx_mosaic_640x480_public/sir/";
    // Base URL of the optional local animation converter
    // (converter/drizzle_gif_converter.py). Point this at the host running the
    // converter on your network.
    const FRAME_CONVERTER_BASE = "http://localhost:8798/frame/";
    const ANIMATION_FRAME_COUNT = 6;

    const PRIMARY_KEYS = [
        "USA",
        "NORTHWEST",
        "NORTHCENTRAL",
        "NORTHEAST",
        "SOUTHWEST",
        "SOUTHCENTRAL",
        "SOUTHEAST"
    ];

    const STATE_KEYS = [
        "AL", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
        "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
        "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH",
        "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA",
        "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA",
        "WV", "WI", "WY", "DC"
    ];

    const REGION_FILES = {
        "NORCAL" => "inmasirCAn.gif",
        "CENTRALCAL" => "inmasirCAc.gif",
        "SOCAL" => "inmasirCAs.gif",
        "TXW" => "inmasirTXw.gif",
        "TXE" => "inmasirTXe.gif",
        "TXS" => "inmasirTXs.gif",
        "NORTHEAST" => "inmasirne.gif",
        "NORTHCENTRAL" => "inmasirnc.gif",
        "NORTHWEST" => "inmasirnw.gif",
        "SOUTHEAST" => "inmasirse.gif",
        "SOUTHCENTRAL" => "inmasirsc.gif",
        "SOUTHWEST" => "inmasirsw.gif",
        "USA" => "inmasirus_.gif"
    };

    const DISPLAY_NAMES = {
        "USA" => "USA",
        "NORTHWEST" => "Northwest",
        "NORTHCENTRAL" => "North Central",
        "NORTHEAST" => "Northeast",
        "SOUTHWEST" => "Southwest",
        "SOUTHCENTRAL" => "South Central",
        "SOUTHEAST" => "Southeast",
        "NORCAL" => "N. California",
        "CENTRALCAL" => "C. California",
        "SOCAL" => "S. California",
        "TXW" => "Texas West",
        "TXE" => "Texas East",
        "TXS" => "Texas South",
        "AL" => "Alabama",
        "AZ" => "Arizona",
        "AR" => "Arkansas",
        "CA" => "California",
        "CO" => "Colorado",
        "CT" => "Connecticut",
        "DE" => "Delaware",
        "FL" => "Florida",
        "GA" => "Georgia",
        "ID" => "Idaho",
        "IL" => "Illinois",
        "IN" => "Indiana",
        "IA" => "Iowa",
        "KS" => "Kansas",
        "KY" => "Kentucky",
        "LA" => "Louisiana",
        "ME" => "Maine",
        "MD" => "Maryland",
        "MA" => "Massachusetts",
        "MI" => "Michigan",
        "MN" => "Minnesota",
        "MS" => "Mississippi",
        "MO" => "Missouri",
        "MT" => "Montana",
        "NE" => "Nebraska",
        "NV" => "Nevada",
        "NH" => "New Hampshire",
        "NJ" => "New Jersey",
        "NM" => "New Mexico",
        "NY" => "New York",
        "NC" => "North Carolina",
        "ND" => "North Dakota",
        "OH" => "Ohio",
        "OK" => "Oklahoma",
        "OR" => "Oregon",
        "PA" => "Pennsylvania",
        "RI" => "Rhode Island",
        "SC" => "South Carolina",
        "SD" => "South Dakota",
        "TN" => "Tennessee",
        "TX" => "Texas",
        "UT" => "Utah",
        "VT" => "Vermont",
        "VA" => "Virginia",
        "WA" => "Washington",
        "WV" => "West Virginia",
        "WI" => "Wisconsin",
        "WY" => "Wyoming",
        "DC" => "District of Columbia"
    };

    const STATE_REDIRECTS = {
        "CT" => "NY",
        "DE" => "VA",
        "MA" => "NY",
        "MD" => "VA",
        "ME" => "NH",
        "NC" => "SC",
        "NJ" => "PA",
        "RI" => "NY",
        "VT" => "NY",
        "WV" => "VA"
    };

    const STATE_FALLBACKS = {
        "ME" => "NORTHEAST",
        "VT" => "NORTHEAST",
        "NH" => "NORTHEAST",
        "MA" => "NORTHEAST",
        "CT" => "NORTHEAST",
        "RI" => "NORTHEAST",
        "NY" => "NORTHEAST",
        "NJ" => "NORTHEAST",
        "PA" => "NORTHEAST",
        "DE" => "NORTHEAST",
        "MD" => "NORTHEAST",
        "DC" => "NORTHEAST",
        "WA" => "NORTHWEST",
        "OR" => "NORTHWEST",
        "ID" => "NORTHWEST",
        "MT" => "NORTHWEST",
        "WY" => "NORTHWEST",
        "MN" => "NORTHCENTRAL",
        "WI" => "NORTHCENTRAL",
        "MI" => "NORTHCENTRAL",
        "ND" => "NORTHCENTRAL",
        "SD" => "NORTHCENTRAL",
        "NE" => "NORTHCENTRAL",
        "IA" => "NORTHCENTRAL",
        "VA" => "SOUTHEAST",
        "WV" => "SOUTHEAST",
        "NC" => "SOUTHEAST",
        "SC" => "SOUTHEAST",
        "GA" => "SOUTHEAST",
        "FL" => "SOUTHEAST",
        "KY" => "SOUTHEAST",
        "TN" => "SOUTHEAST",
        "TX" => "SOUTHCENTRAL",
        "OK" => "SOUTHCENTRAL",
        "AR" => "SOUTHCENTRAL",
        "LA" => "SOUTHCENTRAL",
        "MO" => "SOUTHCENTRAL",
        "KS" => "SOUTHCENTRAL",
        "MS" => "SOUTHCENTRAL",
        "AL" => "SOUTHCENTRAL",
        "CA" => "SOCAL",
        "NV" => "SOUTHWEST",
        "UT" => "SOUTHWEST",
        "CO" => "SOUTHWEST",
        "AZ" => "SOUTHWEST",
        "NM" => "SOUTHWEST"
    };

    function displayName(key) {
        if (DISPLAY_NAMES.hasKey(key)) {
            return DISPLAY_NAMES[key];
        }
        return key;
    }

    function resolvedKeyForState(state) {
        if (STATE_REDIRECTS.hasKey(state)) {
            return STATE_REDIRECTS[state];
        }
        return state;
    }

    function resolvedLabelForState(state) {
        if (STATE_REDIRECTS.hasKey(state)) {
            return displayName(state) + " > " + displayName(STATE_REDIRECTS[state]);
        }
        return displayName(state);
    }

    function fallbackRegionForState(state) {
        if (STATE_FALLBACKS.hasKey(state)) {
            return STATE_FALLBACKS[state];
        }
        return "USA";
    }

    function resolveRadarUrl(key) {
        if (REGION_FILES.hasKey(key)) {
            return RADAR_BASE + REGION_FILES[key];
        }
        return RADAR_BASE + "inmasir" + key.toLower() + "_.gif";
    }

    function useFrameConverter() {
        return FRAME_CONVERTER_BASE.length() > 0;
    }

    function resolveFrameUrl(key, frameIndex) {
        return FRAME_CONVERTER_BASE + key + "/" + frameIndex + ".png";
    }
}
