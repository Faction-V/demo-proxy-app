# BE-955 Jira Ticket Update

## Ticket: Foreign User Authentication for Demo Proxy App

---

## ✅ COMPLETED WORK

### Phase 1: Foreign User Authentication (✓ DONE)

**Implemented Endpoints:**
1. **GET /user/current-user** - Foreign user authentication
   - Supports X-API-Key + X-User-ID headers
   - Returns complete user profile with stats fields
   - Dual pathway: Foreign auth + Session-based auth

2. **GET /user/membership/current-membership** - Subscription info
   - Returns subscription plan (basic/premium) for foreign users
   - Preserves original session-based proxy behavior
   - Both authentication pathways work independently

3. **GET /user/storyplan-config** - Format settings
   - Fetches storyplan configurations from DynamoDB
   - Transforms to kebab-case matching clojure format
   - Supports both auth methods (headers + query param)

4. **GET /prompts** - Organization prompts
   - Alias endpoint that extracts org_id from API key
   - No org_id required in URL
   - Seeded with 3 sample prompts for testing

5. **POST /configs/guardrails/check/prompt** - Guardrail validation
   - Extracts org_id from X-API-Key header
   - Validates prompts against organization guardrails
   - Handles camelCase and snake_case request bodies
   - Note: Capitol-LLM pre_flight_check endpoint returning 500 (separate issue)

**Infrastructure & Tooling:**
- ✅ Environment validation script (`check-env.sh`)
- ✅ Service orchestration (`just start-services`, `just stop-services`)
- ✅ Foreign user testing script (`test-foreign-user.sh`)
- ✅ Frontend local development setup (react-lib from source)
- ✅ Sample data seeding in setup-demo command

**Repositories Updated:**
- `demo-proxy-app`: Main proxy application (branch: BE-955-proxy-demo-app-poc)
- `platform-api`: 7 commits with endpoint implementations (branch: BE-955-proxy-demo-app-poc)
- `clj-pg-wrapper`: Foreign user creation endpoint

---

## 🚧 DISCOVERED SCOPE: GOFAPI MIGRATION

### Key Finding
During testing, discovered that the **frontend library makes calls to gofapi endpoints** that don't exist in platform-api yet. This is part of a **larger gofapi → platform-api migration effort**.

### Migration Documentation Created
- **GOFAPI_MIGRATION.md** - Complete migration tracking document
- **SESSION_SUMMARY.md** - Updated with migration context
- Both committed to demo-proxy-app repository

---

## ❌ BLOCKING ISSUES - NEXT PHASE REQUIRED

### Priority 1: Story Management Endpoints (HIGH - Blocking Frontend)

The following gofapi endpoints are being called by the frontend but return 404:

1. **GET /list?sources=true**
   - Lists user stories
   - Location: `gofapi/src/clj/gofapi/stories/routes.clj`
   - Frontend: Dashboard, story list views
   - **Impact**: Users can't see their stories

2. **GET /mini?migrate=true&story-id={uuid}**
   - Story mini view/preview
   - Location: `gofapi/src/clj/gofapi/stories/routes.clj`
   - Frontend: Story preview, quick access
   - **Impact**: Users can't preview stories

3. **POST /prompt**
   - Creates/triggers story generation
   - Location: `gofapi/src/clj/gofapi/stories/routes.clj`
   - Frontend: Story creation workflow
   - **Impact**: Users can't create new stories

4. **GET /events?story-id={uuid}**
   - Fetches story events/activity logs
   - Location: `gofapi/src/clj/gofapi/events/routes.clj`
   - Frontend: Activity logs, story history
   - **Impact**: Users can't see story activity

**Estimated Effort**: 2-3 days
- Story schema/models design
- DynamoDB or Postgres storage decision
- Story generation integration with capitol-llm
- Event logging system implementation

### Priority 2: Visualizations (MEDIUM)

5. **GET /v2?orgid={uuid}&erid={uuid}&l=...**
   - Tako chart preview links
   - Location: `gofapi/src/clj/gofapi/tako/routes.clj`
   - Frontend: Chart/visualization rendering
   - **Impact**: Charts don't render

**Estimated Effort**: 1-2 days

### Priority 3: Extended Story Features (LOW-MEDIUM)

6. Story CRUD operations (create, update, delete, versions)
7. Credits system endpoints
8. Source attribution management

**Estimated Effort**: 2-3 days

---

## 🎯 RECOMMENDED NEXT STEPS

### Immediate (This Sprint):
1. **Decision**: Choose story storage strategy (DynamoDB vs Postgres)
2. **Decision**: Choose event logging strategy (OpenSearch vs DynamoDB)
3. **Create Epic/Parent Ticket**: "gofapi to platform-api Migration"
4. **Create Child Tickets**:
   - BE-XXX: Migrate Story Management Endpoints
   - BE-XXX: Migrate Events System
   - BE-XXX: Migrate Tako Charts/Visualizations

### Short-term (Next Sprint):
5. Implement Priority 1 endpoints (story management)
6. Frontend integration testing
7. Performance benchmarking vs gofapi

### Medium-term (2-4 weeks):
8. Implement Priority 2 endpoints (visualizations)
9. Implement Priority 3 endpoints (extended features)
10. Parallel run setup (gofapi + platform-api)
11. Traffic migration planning

---

## 📊 MIGRATION STATUS SUMMARY

**Total Endpoints Identified**: ~15-20
**Completed**: 5 endpoints (User auth, prompts, guardrails)
**In Progress**: 0
**Pending**: 10-15 endpoints (Story, events, charts, credits, sources)

**Completion**: ~25% (Auth foundation complete)
**Remaining Effort**: 6-10 days (depending on complexity)

---

## 🔗 RELATED LINKS

- **Demo Proxy Repo**: [Branch BE-955-proxy-demo-app-poc](https://github.com/Faction-V/demo-proxy-app/tree/BE-955-proxy-demo-app-poc)
- **Platform API Repo**: [Branch BE-955-proxy-demo-app-poc](https://github.com/Faction-V/platform-api/tree/BE-955-proxy-demo-app-poc)
- **Migration Doc**: `demo-proxy-app/GOFAPI_MIGRATION.md`
- **Session Summary**: `demo-proxy-app/SESSION_SUMMARY.md`

---

## 💡 TECHNICAL NOTES

### Authentication Pattern
All migrated endpoints support **dual authentication**:
1. Foreign User Auth: `X-API-Key` + `X-User-ID` headers
2. Session Auth: Cookie-based (backward compatibility)

### Data Isolation
- Foreign users are isolated per organization
- Each org_id has independent data space
- Credits tracked at organization level

### Testing Strategy
- Unit tests for both auth methods
- Integration tests with demo-proxy-app
- Frontend e2e tests
- Performance benchmarking

---

## ⚠️ RISKS & BLOCKERS

1. **Capitol-LLM Issue**: Pre-flight check returning 500 (guardrails endpoint partially broken)
2. **Story Storage Decision**: Delays implementation if not decided quickly
3. **Scope Creep**: Migration is larger than originally estimated
4. **gofapi Dependency**: Frontend still needs gofapi until migration complete

---

## 📝 ACCEPTANCE CRITERIA (UPDATED)

### Original Criteria (✓ COMPLETED):
- ✅ Foreign user can authenticate with X-API-Key + X-User-ID
- ✅ Users auto-created on first request
- ✅ Organization provisioned in clj-wrapper
- ✅ Demo application configured and working
- ✅ Documentation complete

### Extended Criteria (🚧 DISCOVERED):
- ❌ All frontend story operations work without gofapi
- ❌ Story list, preview, creation functional
- ❌ Event logging operational
- ❌ Charts/visualizations render correctly
- ❌ Performance comparable to gofapi
- ❌ Zero data loss during migration

---

## 🏁 RECOMMENDATION

**Move BE-955 to "Done"** - Original scope (foreign user auth) is complete and working.

**Create new Epic**: "gofapi to platform-api Migration"
- Link BE-955 as foundational work
- Create child tickets for each endpoint group
- Prioritize story management endpoints first (blocking frontend)

This provides clear separation between:
1. Auth foundation (✅ complete)
2. Endpoint migration (🚧 in progress)

**Status**: Ready for merge to develop after review
**Branches**: BE-955-proxy-demo-app-poc (demo-proxy-app, platform-api)
