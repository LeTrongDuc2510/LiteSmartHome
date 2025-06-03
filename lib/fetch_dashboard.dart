import 'package:thingsboard_client/thingsboard_client.dart';

const thingsBoardApiEndpoint = 'https://app.coreiot.io/';

void main() async {
  print('Hello Core IOT');
  var tbClient = ThingsboardClient(thingsBoardApiEndpoint);

  const String token =
      "eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiJkdWMubGV0cm9uZzI1MTBAaGNtdXQuZWR1LnZuIiwidXNlcklkIjoiMDQwODk5ODAtZTFkOS0xMWVmLWFkMDktNTE1Zjc5MGVkOWRmIiwic2NvcGVzIjpbIlRFTkFOVF9BRE1JTiJdLCJzZXNzaW9uSWQiOiJhNjNjYWNhMy01NDI1LTRlNTctYTExZi0wNWJkOGUzYjEwM2YiLCJleHAiOjE3NDg0MDQyMTcsImlzcyI6ImNvcmVpb3QuaW8iLCJpYXQiOjE3NDgzOTUyMTcsImZpcnN0TmFtZSI6IsSQ4buoQyIsImxhc3ROYW1lIjoiTMOKIFRS4buMTkciLCJlbmFibGVkIjp0cnVlLCJpc1B1YmxpYyI6ZmFsc2UsInRlbmFudElkIjoiMDNmZGViMjAtZTFkOS0xMWVmLWFkMDktNTE1Zjc5MGVkOWRmIiwiY3VzdG9tZXJJZCI6IjEzODE0MDAwLTFkZDItMTFiMi04MDgwLTgwODA4MDgwODA4MCJ9.UPz-r_a0WAK1cUA8oDKoy_mTVG0NpaQ3k82Bj0S9Xi7c6ynnYWadfUBS9QK6ryct_XLuyp2thJsTIXLLrxH9Kg";

  await tbClient.setUserFromJwtToken(token, "", false);
  // print('User set successfully');
  // final authUser = await tbClient.getAuthUser();
  // print('$authUser');

  print('isAuthenticated=${tbClient.isAuthenticated()}');

  print('authUser: ${tbClient.getAuthUser()}');

  // Get user details of current logged in user
  var currentUserDetails = await tbClient.getUserService().getUser();
  print('currentUserDetails: $currentUserDetails');

// fetch dashboards

//   var pageLink = PageLink(10);
//   PageData<DashboardInfo> dashboards;

//   dashboards =
//       await tbClient.getDashboardService().getTenantDashboards(pageLink);
//   print('dashboards: $dashboards');

//   // Replace with the dashboard ID you're interested in
//   final dashboardId = DashboardId('d698b3a0-fa64-11ef-a887-6d1a184f2bb5');

// // Get full dashboard details
//   var dashboard = await tbClient
//       .getDashboardService()
//       .getDashboard('c9fdb6f0-e1db-11ef-ad09-515f790ed9df');

//   print('Dashboard title: ${dashboard?.title}');
//   print('Dashboard configuration: ${dashboard?.configuration}');

// fetch devices

  var entityFilter = EntityTypeFilter(entityType: EntityType.DEVICE);

  // Create key filter to query only active devices
  var activeDeviceKeyFilter = KeyFilter(
      key: EntityKey(type: EntityKeyType.ATTRIBUTE, key: 'active'),
      valueType: EntityKeyValueType.BOOLEAN,
      predicate: BooleanFilterPredicate(
          operation: BooleanOperation.EQUAL,
          value: FilterPredicateValue(true)));

  // // Prepare list of queried device fields
  var deviceFields = <EntityKey>[
    EntityKey(type: EntityKeyType.ENTITY_FIELD, key: 'name'),
    EntityKey(type: EntityKeyType.ENTITY_FIELD, key: 'type'),
    EntityKey(type: EntityKeyType.ENTITY_FIELD, key: 'createdTime'),
  ];

  // Prepare list of queried device attributes
  var deviceAttributes = <EntityKey>[
    EntityKey(type: EntityKeyType.ATTRIBUTE, key: 'active'),
    EntityKey(type: EntityKeyType.ATTRIBUTE, key: 'value'),
  ];

  // Create entity query with provided entity filter, key filter, queried fields and page link
  var devicesQuery = EntityDataQuery(
      entityFilter: entityFilter,
      keyFilters: [activeDeviceKeyFilter],
      entityFields: deviceFields,
      latestValues: deviceAttributes,
      pageLink: EntityDataPageLink(pageSize: 10));

  PageData<EntityData> devices;
  do {
    // Fetch active devices using entities query with current page link
    devices = await tbClient
        .getEntityQueryService()
        .findEntityDataByQuery(devicesQuery);
    print('Active devices entities data:');
    devices.data.forEach((device) {
      print(
          'id: ${device.entityId.id}, createdTime: ${device.createdTime}, name: ${device.field('name')!}, type: ${device.field('type')!}, active: ${device.attribute('active')}, value: ${device.attribute('value')!}');
    });
    devicesQuery = devicesQuery.next();
  } while (devices.hasNext);
}
