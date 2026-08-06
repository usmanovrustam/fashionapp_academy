"""Maps the fashion-product-images dataset labels onto Sylyo's app taxonomy.

The app's ClothingCategory / Season enums live in
fashionapp/Domain/Entities/ClothingEnums.swift. The category label space the
model predicts is a subset of ClothingCategory (only the cases that have
training data in this dataset). Attribute heads (gender / season / usage /
colour) use vocabularies derived from the data at build time.
"""
from __future__ import annotations

# Only these masterCategories are wardrobe-relevant (drop Personal Care,
# Free Items, Home, Sporting Goods, etc.).
KEEP_MASTER_CATEGORIES = {"Apparel", "Footwear", "Accessories"}

# articleType (lowercased) -> ClothingCategory rawValue (see ClothingEnums.swift)
ARTICLE_TYPE_TO_CATEGORY = {
    # tops
    "tshirts": "top", "shirts": "top", "tops": "top", "tunics": "top",
    "kurtas": "top", "kurtis": "top", "sweatshirts": "top", "sweaters": "top",
    "shrug": "top", "camisoles": "top", "blouse": "top", "waistcoat": "top",
    "nehru jackets": "jacket", "tank tops": "top", "henley": "top",
    "kurta sets": "top", "clothing set": "top", "suspenders": "accessories",
    # bottoms
    "jeans": "bottom", "trousers": "bottom", "shorts": "bottom",
    "track pants": "bottom", "capris": "bottom", "leggings": "bottom",
    "skirts": "bottom", "patiala": "bottom", "churidar": "bottom",
    "jeggings": "bottom", "salwar": "bottom", "rain trousers": "bottom",
    "stockings": "bottom", "tights": "bottom", "swimwear bottom": "swimwear",
    # dresses
    "dresses": "dress", "jumpsuit": "dress", "sarees": "dress",
    "gowns": "dress", "lehenga choli": "dress", "dungarees": "dress",
    # outerwear
    "jackets": "jacket", "blazers": "jacket", "rain jacket": "jacket",
    "coats": "coat",
    # shoes
    "casual shoes": "shoes", "sports shoes": "shoes", "formal shoes": "shoes",
    "heels": "shoes", "flats": "shoes", "flip flops": "shoes",
    "sandals": "shoes", "sports sandals": "shoes", "boots": "shoes",
    # bags
    "handbags": "bag", "backpacks": "bag", "clutches": "bag",
    "laptop bag": "bag", "messenger bag": "bag", "duffel bag": "bag",
    "trolley bag": "bag", "waist pouch": "bag", "mobile pouch": "bag",
    "tablet sleeve": "bag", "rucksacks": "bag", "travel accessory": "bag",
    # headwear / neckwear
    "caps": "hat", "hat": "hat", "beanie": "hat",
    "scarves": "scarf", "mufflers": "scarf", "stoles": "scarf",
    "dupatta": "scarf", "ties": "accessories", "tie": "accessories",
    # jewelry
    "earrings": "jewelry", "necklace and chains": "jewelry", "ring": "jewelry",
    "bracelet": "jewelry", "pendant": "jewelry", "jewellery set": "jewelry",
    "bangle": "jewelry", "bangles": "jewelry", "cufflinks": "jewelry",
    # accessories
    "watches": "watch", "belts": "belt", "sunglasses": "accessories",
    "wallets": "accessories", "gloves": "accessories", "headband": "accessories",
    "socks": "accessories", "accessory gift set": "accessories",
    "hair accessory": "accessories", "hair band": "accessories",
    "umbrellas": "accessories", "key chain": "accessories",
    # sleep / swim / formal
    "nightdress": "sleepwear", "night suits": "sleepwear",
    "lounge pants": "sleepwear", "lounge tshirts": "sleepwear",
    "lounge shorts": "sleepwear", "loungewear and nightwear": "sleepwear",
    "innerwear vests": "sleepwear", "briefs": "sleepwear", "boxers": "sleepwear",
    "trunk": "sleepwear", "bra": "sleepwear",
    "swimwear": "swimwear",
    "suits": "formalwear",
}

# subCategory (lowercased) -> ClothingCategory rawValue (fallback when the
# articleType is unknown).
SUBCATEGORY_TO_CATEGORY = {
    "topwear": "top", "bottomwear": "bottom", "shoes": "shoes",
    "sandal": "shoes", "flip flops": "shoes", "bags": "bag",
    "watches": "watch", "belts": "belt", "jewellery": "jewelry",
    "eyewear": "accessories", "headwear": "hat", "scarves": "scarf",
    "ties": "accessories", "socks": "accessories", "gloves": "accessories",
    "wallets": "accessories", "dress": "dress", "loungewear and nightwear": "sleepwear",
    "innerwear": "sleepwear", "saree": "dress", "apparel set": "top",
    "accessories": "accessories", "sports accessories": "accessories",
    "sports equipment": "other", "stoles": "scarf", "muffler": "scarf",
}

# dataset gender -> normalized gender class
GENDER_MAP = {
    "Men": "Men", "Women": "Women", "Unisex": "Unisex",
    "Boys": "Kids", "Girls": "Kids",
}

# dataset season -> app Season rawValue (see ClothingEnums.swift)
SEASON_MAP = {
    "Spring": "spring", "Summer": "summer",
    "Fall": "autumn", "Winter": "winter",
}


def map_category(article_type: str | None, sub_category: str | None) -> str | None:
    at = (article_type or "").strip().lower()
    if at in ARTICLE_TYPE_TO_CATEGORY:
        return ARTICLE_TYPE_TO_CATEGORY[at]
    sc = (sub_category or "").strip().lower()
    if sc in SUBCATEGORY_TO_CATEGORY:
        return SUBCATEGORY_TO_CATEGORY[sc]
    return None
