import Foundation

/// Từ tiếng Anh thông dụng **cắt được hết thành âm tiết romaji** (game, time, kate, tomato…) — `VieNeuJapaneseNameReader`
/// loại chúng ra để không đọc nhầm theo âm tiết kiểu Nhật.
///
/// **File sinh tự động** bằng `Scripts/gen_vieneu_romaji_english_lookalikes.py` từ 10.000 từ tiếng Anh phổ biến nhất
/// (`top_words.rs` của sea-g2p, Apache-2.0, gốc google-10000-english). Đừng sửa tay: sửa luật cắt âm tiết trong
/// `VieNeuRomajiSyllabifier` thì sửa bản chép trong script rồi sinh lại.
enum VieNeuRomajiEnglishLookalikes {
    /// 507 từ, chữ thường.
    static let words: Set<String> = [
        "aaron", "abuse", "adobe", "again", "agenda", "amanda", "amazon", "ambien", "amino", "animation", "anna",
        "anne", "annie", "annotation", "antenna", "anti", "antigua", "antonio", "anyone", "arabia", "area", "arena",
        "arise", "arizona", "aruba", "asia", "asian", "aside", "asin", "assume", "assure", "attention", "attitude",
        "audi", "audio", "aurora", "auto", "automation", "aware", "awesome", "babe", "banana", "bare", "base",
        "basename", "basin", "bean", "began", "begin", "begun", "benjamin", "beside", "beta", "bike", "bikini",
        "bingo", "bite", "bondage", "bone", "bureau", "button", "chain", "champion", "change", "chase", "china",
        "chinese", "choose", "chose", "chosen", "dakota", "damage", "dame", "dana", "dare", "data", "database",
        "date", "dean", "debate", "debian", "demo", "dense", "desire", "diana", "diane", "diego", "dimension",
        "disease", "domain", "dome", "donate", "donation", "done", "donna", "dosage", "dose", "dozen", "dubai",
        "dude", "duke", "duration", "ease", "echo", "eden", "edition", "emission", "empire", "engage", "engine",
        "ensure", "entire", "episode", "eugene", "euro", "europe", "european", "fusion", "future", "gage", "gain",
        "game", "garage", "gate", "gauge", "gazette", "gene", "generate", "generation", "genome", "genre", "genuine",
        "gone", "gonna", "gore", "goto", "gotta", "gotten", "guarantee", "guide", "guinea", "guru", "guyana", "haiti",
        "hansen", "happen", "hate", "hawaii", "hawaiian", "here", "herein", "heritage", "hero", "hide", "hindu",
        "hire", "home", "homepage", "hope", "horizon", "hose", "house", "huge", "hugo", "human", "humanitarian",
        "hungarian", "hyundai", "idaho", "idea", "ieee", "image", "imagination", "imagine", "impose", "india",
        "indian", "indiana", "indie", "indonesia", "indonesian", "inside", "intake", "intense", "intention",
        "intimate", "into", "iowa", "iran", "iron", "issue", "jade", "jake", "jamie", "jane", "japan", "japanese",
        "jason", "joan", "johnson", "join", "joke", "jose", "joshua", "juan", "june", "karen", "kate", "katie",
        "keno", "kenya", "kinase", "kinda", "korea", "korean", "machine", "made", "madison", "madonna", "magazine",
        "maiden", "main", "maine", "maintain", "make", "mambo", "manage", "mandate", "manhattan", "manitoba", "maria",
        "marie", "marijuana", "marina", "marine", "mario", "marion", "maritime", "mason", "massage", "mate", "mature",
        "maui", "mean", "measure", "media", "median", "mediawiki", "meditation", "mega", "memo", "mention", "menu",
        "mere", "mesa", "message", "meta", "metadata", "miami", "michigan", "midi", "mike", "mime", "mine", "mini",
        "miniature", "minimize", "minnesota", "minute", "mission", "mississippi", "missouri", "mode", "moderate",
        "mono", "monroe", "montana", "monte", "moore", "more", "motion", "mountain", "mouse", "mumbai", "muze",
        "name", "namibia", "nano", "nasa", "nation", "nationwide", "nato", "nature", "negotiation", "neon", "niagara",
        "nigeria", "nike", "nine", "node", "noise", "nokia", "nomination", "none", "nose", "note", "notion", "nude",
        "nuke", "nutten", "ohio", "omaha", "oman", "omega", "onion", "ontario", "onto", "open", "opera", "operate",
        "operation", "opinion", "opposite", "opposition", "orange", "oregon", "orientation", "origin", "ottawa",
        "owen", "ozone", "page", "pain", "panama", "papua", "para", "parade", "paradise", "paso", "passage",
        "passion", "patio", "penguin", "pension", "peru", "pete", "petite", "petition", "piano", "pike", "pine",
        "pipe", "poison", "pope", "pose", "position", "possession", "potato", "pure", "radiation", "radio", "rage",
        "rain", "raise", "range", "rape", "rare", "rate", "ratio", "reason", "rebate", "refuse", "regime", "region",
        "remain", "remote", "reno", "reputation", "resume", "retain", "retention", "reunion", "ride", "ripe", "rise",
        "robin", "robinson", "roman", "romania", "rome", "rope", "rosa", "rose", "rotation", "rouge", "route",
        "routine", "runtime", "russia", "russian", "sage", "sake", "samba", "same", "samoa", "santa", "sara", "satin",
        "saudi", "sean", "season", "semi", "senate", "sense", "separate", "separation", "session", "shade", "shake",
        "shakira", "shame", "shannon", "shape", "share", "shareware", "sharon", "shine", "shoe", "shopee", "shore",
        "side", "simon", "singapore", "site", "situation", "size", "soma", "some", "someone", "sudan", "suite",
        "sunrise", "sunshine", "suppose", "sure", "susan", "suse", "tahoe", "taiwan", "take", "taken", "tampa",
        "tanzania", "tape", "tattoo", "teenage", "temperature", "tennessee", "tension", "tide", "time", "tion",
        "tire", "tissue", "titten", "tobago", "token", "tomato", "tone", "tongue", "toronto", "tube", "tuition",
        "tune", "tunisia", "uganda", "undo", "union", "unto", "upon", "usage", "wage", "wagon", "wake", "wanna",
        "ware", "warehouse", "weapon", "were", "wichita", "wide", "wiki", "wikipedia", "wine", "wire", "wise",
        "woman", "women", "wooden", "yahoo", "yoga", "youtube", "yukon", "zambia", "zero", "zone", "zope",
    ]
}
