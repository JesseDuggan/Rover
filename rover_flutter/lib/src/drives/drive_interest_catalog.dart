class DriveInterestCategory {
  const DriveInterestCategory(this.id, this.label, this.children);
  final String id, label;
  final Map<String, String> children;
}

const driveCategories = [
  DriveInterestCategory('scenic', 'Scenic Views & Drives', {
    'scenic.coast': 'Coastal landmarks',
    'scenic.mountains': 'Mountain views',
    'scenic.countryside': 'Countryside',
    'scenic.panoramas': 'Panoramic viewpoints',
  }),
  DriveInterestCategory('nature', 'Parks, Lakes & Nature', {
    'nature.national_parks': 'National parks',
    'nature.lakes': 'Lakes',
    'nature.waterfalls': 'Waterfalls',
    'nature.forests': 'Forests & gardens',
  }),
  DriveInterestCategory('history', 'History & Heritage', {
    'history.castles': 'Castles',
    'history.museums': 'History museums',
    'history.monuments': 'Monuments',
    'history.ruins': 'Ancient sites',
  }),
  DriveInterestCategory('towns', 'Towns & Villages', {
    'towns.old_towns': 'Old towns',
    'towns.villages': 'Picturesque villages',
    'towns.harbours': 'Fishing villages & harbours',
    'towns.market_towns': 'Market towns',
  }),
  DriveInterestCategory('food', 'Food & Local Discoveries', {
    'food.restaurants': 'Local restaurants',
    'food.cafes': 'Cafes & bakeries',
    'food.markets': 'Food markets',
    'food.farm_shops': 'Farm shops',
  }),
  DriveInterestCategory('outdoors', 'Outdoor Adventures', {
    'outdoors.short_walks': 'Short walks',
    'outdoors.hiking': 'Hiking trails',
    'outdoors.picnics': 'Picnic spots',
    'outdoors.water': 'Water activities',
  }),
  DriveInterestCategory('attractions', 'Attractions & Hidden Gems', {
    'attractions.unusual': 'Unusual landmarks',
    'attractions.gardens': 'Botanical gardens',
    'attractions.caves': 'Caves',
    'attractions.local_gems': 'Local discoveries',
  }),
  DriveInterestCategory('wildlife', 'Wildlife & Animals', {
    'wildlife.reserves': 'Wildlife reserves',
    'wildlife.birds': 'Birdwatching',
    'wildlife.aquariums': 'Aquariums',
    'wildlife.sanctuaries': 'Animal sanctuaries',
  }),
  DriveInterestCategory('family', 'Family & Fun', {
    'family.playgrounds': 'Playgrounds',
    'family.interactive': 'Interactive museums',
    'family.theme_parks': 'Theme parks',
    'family.family_parks': 'Family parks',
  }),
  DriveInterestCategory('shopping', 'Shopping & Local Finds', {
    'shopping.crafts': 'Crafts & local makers',
    'shopping.antiques': 'Antiques',
    'shopping.regional': 'Regional products',
    'shopping.markets': 'Street markets',
  }),
  DriveInterestCategory('relaxation', 'Relaxation & Getaways', {
    'relaxation.beaches': 'Quiet beaches',
    'relaxation.spas': 'Spas',
    'relaxation.gardens': 'Peaceful gardens',
    'relaxation.retreats': 'Countryside retreats',
  }),
  DriveInterestCategory('art', 'Art & Architecture', {
    'art.galleries': 'Art galleries',
    'art.public_art': 'Public art',
    'art.buildings': 'Distinctive buildings',
    'art.churches': 'Churches & cathedrals',
  }),
];
