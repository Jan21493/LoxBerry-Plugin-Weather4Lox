// Missing precipitation values remain visibly unknown, rather than becoming zero.
function formatPrecipitation(amount, probability) {
  return (amount != null ? amount : '--') + ' mm · ' +
    (probability != null ? probability : '--') + '%';
}

function describeCloudCover(description, cloudCover) {
  var label = liveData.lang && liveData.lang.theme && liveData.lang.theme.cloud_cover;
  return (description || '--') +
    (cloudCover != null ? ', ' + (label || 'Cloud cover') + ' ' + cloudCover + '%' : '');
}
