# Frontend Architecture

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | **Next.js 14** (App Router) |
| Styling | **Tailwind CSS** |
| Component Library | **shadcn/ui** |
| Charts | **Recharts** |
| State Management | **Zustand** |
| Data Fetching | **TanStack Query** (React Query) |
| Forms | **React Hook Form** + **Zod** |
| HTTP Client | **fetch** with JWT auth wrapper |
| Type Safety | **TypeScript** |

---

## Routing Structure

### Public Routes

| Route | Description |
|---|---|
| `/` | Marketing landing page |
| `/pricing` | Pricing tiers (Starter/Growth/Pro) |
| `/login` | Redirects to Shopify OAuth flow |

### Authenticated Routes

| Route | Description |
|---|---|
| `/dashboard` | Overview: revenue, AOV, orders, insights |
| `/dashboard/products` | Product performance table |
| `/dashboard/customers` | Customer segmentation (CLV, churn risk) |
| `/dashboard/insights` | AI-generated insights feed |
| `/dashboard/settings` | Store settings, disconnect |

### Middleware

**`middleware.ts`:**

```typescript
import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export function middleware(request: NextRequest) {
  const token = request.cookies.get('auth_token')?.value;

  if (request.nextUrl.pathname.startsWith('/dashboard') && !token) {
    return NextResponse.redirect(new URL('/login', request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: '/dashboard/:path*',
};
```

---

## Components (shadcn/ui)

### `<MetricCard />`

Displays key metrics (revenue, AOV, orders count).

```typescript
interface MetricCardProps {
  title: string;
  value: string | number;
  change?: number; // percentage change vs previous period
  icon?: React.ReactNode;
  loading?: boolean;
}
```

```tsx
<MetricCard
  title="Total Revenue"
  value="$12,340"
  change={+15.3}
  icon={<DollarSign />}
/>
```

---

### `<RevenueChart />`

Line chart showing revenue over time (Recharts `<LineChart>`).

```typescript
interface RevenueChartProps {
  data: Array<{ date: string; revenue: number }>;
  period: '7d' | '30d' | '90d';
  loading?: boolean;
}
```

```tsx
<RevenueChart data={revenueData} period="30d" />
```

---

### `<InsightCard />`

Displays an AI-generated insight with severity badge and action button.

```typescript
interface InsightCardProps {
  insight: {
    id: string;
    type: 'revenue' | 'product' | 'customer' | 'churn';
    severity: 'info' | 'warning' | 'critical';
    message: string;
    metadata?: Record<string, any>;
    created_at: string;
    is_read: boolean;
  };
  onMarkAsRead: (id: string) => void;
}
```

**Badge colors:**
- `info` → blue
- `warning` → yellow
- `critical` → red

Includes “Mark as read” button and optional action (e.g., “View product”, “Export customers”).

---

### `<ProductTable />`

Sortable table showing product performance.

```typescript
interface ProductTableProps {
  products: Array<{
    id: string;
    name: string;
    revenue: number;
    orders: number;
    units_sold: number;
    avg_price: number;
    trend: number; // percentage change vs last period
  }>;
  loading?: boolean;
  onSort: (column: string, direction: 'asc' | 'desc') => void;
}
```

**Columns:** Product Name, Revenue, Orders, Units Sold, Avg Price, Trend (↑ or ↓ with %)

**Features:** Sortable by any column, pagination (20/page), search bar

---

### `<CustomerTable />`

Sortable table showing customer segmentation.

```typescript
interface CustomerTableProps {
  customers: Array<{
    id: string;
    email: string;
    name: string;
    total_spent: number;
    orders: number;
    clv: number;
    churn_risk: number; // 0–1
    last_order_at: string;
  }>;
  loading?: boolean;
  onSort: (column: string, direction: 'asc' | 'desc') => void;
}
```

**Columns:** Customer Name, Email, Total Spent, Orders, CLV (predicted), Churn Risk (badge: low/medium/high), Last Order

**Features:** Sortable, pagination, filter by churn risk level

---

### `<WeeklySummary />`

Collapsible panel showing last week’s summary.

```typescript
interface WeeklySummaryProps {
  summary: {
    revenue: number;
    revenue_change: number;
    orders: number;
    orders_change: number;
    customers: number;
    customers_change: number;
    top_products: Array<{ name: string; revenue: number }>;
    insights: Insight[];
  };
}
```

Rendered as a shadcn/ui `<Accordion>` — shows key weekly metrics + top 3 insights, expandable for full report.

---

## State Management (Zustand)

### `stores/auth.ts`

```typescript
import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface AuthStore {
  storeId: string | null;
  storeDomain: string | null;
  token: string | null;
  isAuthenticated: boolean;
  login: (token: string, storeId: string, storeDomain: string) => void;
  logout: () => void;
}

export const useAuthStore = create<AuthStore>()(
  persist(
    (set) => ({
      storeId: null,
      storeDomain: null,
      token: null,
      isAuthenticated: false,
      login: (token, storeId, storeDomain) =>
        set({ token, storeId, storeDomain, isAuthenticated: true }),
      logout: () =>
        set({ token: null, storeId: null, storeDomain: null, isAuthenticated: false }),
    }),
    { name: 'auth-storage' }
  )
);
```

---

### `stores/insights.ts`

```typescript
import { create } from 'zustand';

interface Insight {
  id: string;
  type: 'revenue' | 'product' | 'customer' | 'churn';
  severity: 'info' | 'warning' | 'critical';
  message: string;
  metadata?: Record<string, any>;
  created_at: string;
  is_read: boolean;
}

interface InsightsStore {
  insights: Insight[];
  unreadCount: number;
  loading: boolean;
  fetchInsights: () => Promise<void>;
  markAsRead: (id: string) => Promise<void>;
}

export const useInsightsStore = create<InsightsStore>((set, get) => ({
  insights: [],
  unreadCount: 0,
  loading: false,
  fetchInsights: async () => {
    set({ loading: true });
    const data = await fetchAPI('/insights');
    set({
      insights: data.insights,
      unreadCount: data.insights.filter((i: Insight) => !i.is_read).length,
      loading: false,
    });
  },
  markAsRead: async (id: string) => {
    await fetchAPI(`/insights/${id}/read`, { method: 'POST' });
    set((state) => ({
      insights: state.insights.map((i) =>
        i.id === id ? { ...i, is_read: true } : i
      ),
      unreadCount: state.unreadCount - 1,
    }));
  },
}));
```

---

### `stores/dashboard.ts`

```typescript
import { create } from 'zustand';

interface DashboardStore {
  period: '7d' | '30d' | '90d';
  setPeriod: (period: '7d' | '30d' | '90d') => void;
}

export const useDashboardStore = create<DashboardStore>((set) => ({
  period: '30d',
  setPeriod: (period) => set({ period }),
}));
```

---

## API Client

### `lib/api.ts`

```typescript
const BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000';

export class APIError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export async function fetchAPI<T = any>(
  endpoint: string,
  options: RequestInit = {}
): Promise<T> {
  const token = getToken();

  const res = await fetch(`${BASE_URL}${endpoint}`, {
    ...options,
    headers: {
      Authorization: token ? `Bearer ${token}` : '',
      'Content-Type': 'application/json',
      ...options.headers,
    },
    credentials: 'include',
  });

  if (!res.ok) {
    const error = await res.json().catch(() => ({ detail: 'Unknown error' }));
    throw new APIError(res.status, error.detail || `HTTP ${res.status}`);
  }

  return res.json();
}

function getToken(): string | null {
  if (typeof window === 'undefined') return null;
  return (
    document.cookie
      .split('; ')
      .find((row) => row.startsWith('auth_token='))
      ?.split('=')[1] || null
  );
}
```

---

## Data Fetching (TanStack Query)

### `hooks/useDashboardMetrics.ts`

```typescript
import { useQuery } from '@tanstack/react-query';
import { fetchAPI } from '@/lib/api';
import { useDashboardStore } from '@/stores/dashboard';

export function useDashboardMetrics() {
  const period = useDashboardStore((state) => state.period);

  return useQuery({
    queryKey: ['dashboard-metrics', period],
    queryFn: () => fetchAPI(`/metrics/revenue?period=${period}`),
    staleTime: 5 * 60 * 1000,   // 5 minutes
    refetchInterval: 60 * 1000, // 1 minute
  });
}
```

**Usage:**

```tsx
const { data, isLoading, error } = useDashboardMetrics();

if (isLoading) return <Skeleton />;
if (error) return <ErrorAlert message={error.message} />;

return <MetricCard title="Revenue" value={data.revenue} />;
```

---

## Layout

### `app/dashboard/layout.tsx`

```tsx
import { Sidebar } from '@/components/sidebar';
import { Header } from '@/components/header';

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="flex h-screen">
      <Sidebar />
      <div className="flex flex-col flex-1">
        <Header />
        <main className="flex-1 overflow-y-auto p-6 bg-gray-50">
          {children}
        </main>
      </div>
    </div>
  );
}
```

---

## Error Handling

### Global Error Boundary — `app/error.tsx`

```tsx
'use client';

import { useEffect } from 'react';
import { Button } from '@/components/ui/button';

export default function Error({
  error,
  reset,
}: {
  error: Error;
  reset: () => void;
}) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <div className="flex flex-col items-center justify-center h-screen">
      <h2 className="text-2xl font-bold mb-4">Something went wrong</h2>
      <Button onClick={reset}>Try again</Button>
    </div>
  );
}
```

### API Error Handling via TanStack Query

```typescript
import { QueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      onError: (error: any) => {
        if (error.status === 401) {
          toast.error('Session expired. Please log in again.');
          useAuthStore.getState().logout();
        } else {
          toast.error(error.message || 'An error occurred');
        }
      },
    },
  },
});
```

---

## Authentication Flow

### Shopify OAuth

```
1. User clicks "Connect Store" on landing page
   → Redirect to /api/auth/shopify/install?shop={shop_domain}

2. Backend redirects to Shopify OAuth consent screen

3. Shopify redirects back to /api/auth/shopify/callback?code=...&shop=...

4. Backend exchanges code for access token

5. Backend returns JWT to frontend via Set-Cookie

6. Frontend redirects to /dashboard
```

### Logout

```typescript
const { logout } = useAuthStore();

async function handleLogout() {
  await fetchAPI('/auth/logout', { method: 'POST' });
  logout();
  router.push('/');
}
```

---

## Performance Optimization

### Code Splitting

```tsx
const RevenueChart = dynamic(() => import('@/components/revenue-chart'), {
  loading: () => <Skeleton />,
});
```

### Image Optimization
- Use Next.js `<Image>` component for all images
- Store product images in Cloudflare R2, served via Cloudflare CDN

### Bundle Size
- Keep bundle under **200 KB** (gzipped)
- Tree-shake unused shadcn/ui components
- Lazy-load Recharts

---

## Testing Strategy

| Layer | Tool | Scope |
|---|---|---|
| Unit | Vitest | Zustand stores, utility functions |
| Component | React Testing Library | `<MetricCard />`, `<InsightCard />`, `<ProductTable />` with mocked API |
| E2E | Playwright | Auth flow, dashboard navigation, insight interaction |

---

## Deployment

**Platform:** Vercel

**Environment Variables:**
```
NEXT_PUBLIC_API_URL=https://api.revenueos.com
SHOPIFY_CLIENT_ID=…
SHOPIFY_CLIENT_SECRET=…
```

**Build Command:** `npm run build`  
**Output Directory:** `.next`

Static assets served via **Cloudflare CDN** with edge caching for `/` and `/pricing`.

---

## Accessibility (WCAG 2.1 AA)

- All interactive elements keyboard-accessible
- ARIA labels on all buttons and links
- Color contrast ratio ≥ 4.5:1
- Focus indicators visible
- Screen reader tested with NVDA/JAWS

---

## Roadmap

### Phase 1 (MVP)
- [x] Auth flow (Shopify OAuth)
- [x] Dashboard overview page
- [x] Product table
- [x] Insight feed
- [ ] Customer table
- [ ] Settings page

### Phase 2
- [ ] Real-time notifications (WebSocket)
- [ ] Export to CSV/PDF
- [ ] Dark mode

### Phase 3
- [ ] AI Copilot chat interface
- [ ] Multi-language support (RTL for Arabic)
