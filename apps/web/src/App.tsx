import {
  lazy,
  Suspense,
  useEffect,
  useRef,
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import {
  ArrowDownToLine,
  ArrowLeft,
  ArrowRight,
  ArrowUpRight,
  AudioLines,
  Bell,
  Bookmark,
  CalendarDays,
  Camera,
  Check,
  ChevronDown,
  ChevronRight,
  Clock,
  CloudRain,
  Compass,
  CreditCard,
  Download,
  Earth,
  Footprints,
  Heart,
  HelpCircle,
  Hotel,
  Layers,
  Leaf,
  LoaderCircle,
  Map,
  MapPin,
  MessageCircle,
  Navigation,
  Plus,
  Search,
  Send,
  Settings,
  ShieldCheck,
  SlidersHorizontal,
  Sparkles,
  Sun,
  Users,
  Utensils,
  Wallet,
  X,
  Zap,
} from "lucide-react";
import { api } from "./lib/api";
import GuideReview from "./components/GuideReview";
import LiveBrief from "./components/LiveBrief";
import ReceiptLens from "./components/ReceiptLens";
import Checkout from "./components/Checkout";
import GuideCards, { type GuideCard } from "./components/GuideCards";
import {
  dayLabel,
  destinations,
  expenseTotal,
  storedTrip,
  type GuideProposal,
  fromMinor,
  money,
  photos,
  readLocal,
  sampleTrip,
  writeLocal,
  type Change,
  type Destination,
  type Expense,
  type Stop,
  type Trip,
} from "./lib/model";
const AriScene = lazy(() => import("./components/AriScene"));
const TripMap = lazy(() => import("./components/TripMap"));
type Page =
  | "explore"
  | "trips"
  | "map"
  | "saved"
  | "budget"
  | "crew"
  | "settings"
  | "book"
  | "live"
  | "lens";
type Dialog =
  | "create"
  | "rescue"
  | "assistant"
  | "expense"
  | "notifications"
  | "about"
  | Destination
  | null;
const nav = [
  { id: "explore", label: "Discover", icon: Compass },
  { id: "trips", label: "My trips", icon: Map },
  { id: "map", label: "Map explorer", icon: Earth },
  { id: "saved", label: "Saved places", icon: Bookmark },
  { id: "book", label: "Stays & flights", icon: Hotel },
] as const;
const tools = [
  { id: "live", label: "On the go", icon: Navigation },
  { id: "budget", label: "Trip budget", icon: Wallet },
  { id: "crew", label: "Your crew", icon: Users },
  { id: "lens", label: "Receipt lens", icon: Camera },
] as const;
const pageNames: Record<Page, string> = {
  explore: "Discover",
  trips: "My trips",
  map: "Map explorer",
  saved: "Saved places",
  budget: "Trip budget",
  crew: "Your crew",
  settings: "Your preferences",
  book: "Stays & flights",
  live: "On the go",
  lens: "Receipt lens",
};
function getPage(): Page {
  const p = location.hash.slice(1);
  return p in pageNames ? (p as Page) : "explore";
}

export default function App() {
  const [page, setPage] = useState<Page>(getPage),
    [dialog, setDialog] = useState<Dialog>(null),
    [trip, setTrip] = useState<Trip>(storedTrip);
  const [day, setDay] = useState(0),
    [selected, setSelected] = useState<string | null>(null),
    [saved, setSaved] = useState<string[]>(() => readLocal("arivo.saved", []));
  const [expenses, setExpenses] = useState<Expense[]>(() =>
    readLocal("arivo.expenses." + trip.id, []),
  );
  const [motion, setMotion] = useState(() =>
    readLocal(
      "arivo.motion",
      !matchMedia("(prefers-reduced-motion: reduce)").matches,
    ),
  );
  const [query, setQuery] = useState(""),
    [filter, setFilter] = useState("For you"),
    [toast, setToast] = useState(""),
    [menu, setMenu] = useState(false),
    [draft, setDraft] = useState("");
  const [guideInput, setGuideInput] = useState("");
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const currentDay = trip.days[Math.min(day, trip.days.length - 1)];
  const notify = (message: string) => {
    clearTimeout(timer.current);
    setToast(message);
    timer.current = setTimeout(() => setToast(""), 4500);
  };
  useEffect(() => {
    const handler = () => {
      setPage(getPage());
      setMenu(false);
      setSelected(null);
      window.scrollTo({ top: 0, behavior: "instant" });
    };
    window.addEventListener("hashchange", handler);
    return () => {
      window.removeEventListener("hashchange", handler);
      clearTimeout(timer.current);
    };
  }, []);
  useEffect(() => {
    document.documentElement.dataset.motion = motion ? "on" : "off";
    writeLocal("arivo.motion", motion);
  }, [motion]);
  useEffect(() => {
    setExpenses(readLocal("arivo.expenses." + trip.id, []));
  }, [trip.id]);
  function go(p: Page) {
    location.hash = p;
    setPage(p);
    setMenu(false);
    setSelected(null);
    window.scrollTo({ top: 0, behavior: "instant" });
  }
  function saveTrip(t: Trip) {
    setTrip(t);
    if (!writeLocal("arivo.trip", t))
      notify(
        "Storage is full. This trip is available for this session; download it to keep a copy.",
      );
  }
  function toggleSave(id: string) {
    const next = saved.includes(id)
      ? saved.filter((s) => s !== id)
      : [...saved, id];
    setSaved(next);
    writeLocal("arivo.saved", next);
    notify(
      next.includes(id)
        ? "Saved to your places. A little inspiration for later."
        : "Removed from saved places.",
    );
  }
  function create(text = "") {
    setDraft(text);
    setDialog("create");
  }
  function download() {
    const url = URL.createObjectURL(
      new Blob([JSON.stringify(trip, null, 2)], { type: "application/json" }),
    );
    const a = document.createElement("a");
    a.href = url;
    a.download = `arivo-${trip.cities[0]}-trip.json`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    notify("Your itinerary has been downloaded.");
  }
  function chooseDay(index: number) {
    setDay(index);
    setSelected(null);
  }
  const items = currentDay?.items ?? [];
  const filtered = destinations.filter(
    (d) =>
      (filter === "For you" || filter === "All" || d.category === filter) &&
      `${d.name} ${d.country}`.toLowerCase().includes(query.toLowerCase()),
  );
  const scene = (
    <Suspense
      fallback={
        <img
          className="ari-static"
          src="/mascot/poster_idle.webp"
          alt="Ari, your travel companion"
        />
      }
    >
      <AriScene motion={motion} />
    </Suspense>
  );
  const map = (
    <Suspense
      fallback={
        <div className="map-loading standalone">
          <LoaderCircle className="spin" />
          Loading your map…
        </div>
      }
    >
      <TripMap
        items={items}
        selected={selected}
        onSelect={setSelected}
        motion={motion}
      />
    </Suspense>
  );
  return (
    <div className="app-shell">
      <a
        className="skip-link"
        href="#main-content"
        onClick={(e) => {
          e.preventDefault();
          document.getElementById("main-content")?.focus();
        }}
      >
        Skip to content
      </a>
      {menu && (
        <button
          className="nav-scrim"
          aria-label="Close navigation"
          onClick={() => setMenu(false)}
        />
      )}
      <aside className={`sidebar ${menu ? "open" : ""}`}>
        <a className="brand" href="#explore">
          <span className="brand-mark">
            <Compass size={25} strokeWidth={1.5} />
          </span>
          <span>
            arivo<span className="brand-dot">.</span>
            <small>A WORLD OF POSSIBILITY</small>
          </span>
        </a>
        <button className="button primary new-trip" onClick={() => create()}>
          <Plus size={17} />
          Create a trip
          <ArrowUpRight size={16} />
        </button>
        <span className="nav-eyebrow">YOUR NEXT CHAPTER</span>
        <nav aria-label="Main navigation">
          {nav.map((n) => (
            <a
              key={n.id}
              href={`#${n.id}`}
              className={`nav-item ${page === n.id ? "active" : ""}`}
              aria-current={page === n.id ? "page" : undefined}
            >
              <n.icon size={19} />
              <span>{n.label}</span>
              {n.id === "saved" && saved.length > 0 && (
                <small>{saved.length}</small>
              )}
              {page === n.id && <i />}
            </a>
          ))}
        </nav>
        <span className="nav-eyebrow second">TRAVEL TOGETHER, BETTER</span>
        <nav aria-label="Travel tools">
          {tools.map((n) => (
            <a
              key={n.id}
              href={`#${n.id}`}
              className={`nav-item ${page === n.id ? "active" : ""}`}
              aria-current={page === n.id ? "page" : undefined}
            >
              <n.icon size={18} />
              <span>{n.label}</span>
              {n.id === "live" && <span className="tiny-dot" />}
            </a>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="little-note">
            <Earth size={20} />
            <p>
              Less planning.
              <br />
              <em>More being there.</em>
            </p>
            <span>✧</span>
          </div>
          <button className="nav-item" onClick={() => setDialog("about")}>
            <HelpCircle size={18} />
            About Arivo
          </button>
          <a
            className={`profile ${page === "settings" ? "active" : ""}`}
            href="#settings"
          >
            <span className="avatar">Y</span>
            <span>
              Your travel space<small>Let curiosity lead.</small>
            </span>
            <Settings size={17} />
          </a>
        </div>
      </aside>
      <div className="main-shell">
        <header className="topbar">
          <div className="breadcrumb">
            <button
              className="mobile-menu icon-button"
              aria-label="Open navigation"
              onClick={() => setMenu(true)}
            >
              <Compass />
            </button>
            <span>Your world</span>
            <ChevronRight size={13} />
            <strong>{pageNames[page]}</strong>
          </div>
          <div className="topbar-right">
            <span className="topbar-note">
              <span className="live-dot" />
              Made for the way you travel
            </span>
            <button
              className="icon-button notification-button"
              aria-label="Notifications"
              onClick={() => setDialog("notifications")}
            >
              <Bell size={19} />
              <i />
            </button>
            <button
              className="avatar small"
              aria-label="Open your preferences"
              onClick={() => go("settings")}
            >
              Y
            </button>
          </div>
        </header>
        <main
          id="main-content"
          tabIndex={-1}
          className={`page page-${page}`}
          key={page}
        >
          {page === "explore" && (
            <>
              <div className="welcome-row">
                <div>
                  <span className="eyebrow">
                    <Sun size={14} /> A LITTLE CURIOSITY GOES A LONG WAY
                  </span>
                  <h1>Where will your story go next?</h1>
                </div>
                <span className="date-label">
                  Your next chapter starts here <ArrowUpRight size={16} />
                </span>
              </div>
              <div className="discovery-layout">
                <div className="discovery-main">
                  <section className="hero-card">
                    <img
                      className="hero-photo"
                      src={photos.fuji}
                      alt="Traditional street and Yasaka Pagoda in Kyoto"
                      fetchPriority="high"
                    />
                    <div className="hero-shade" />
                    <div className="hero-copy">
                      <span className="hero-eyebrow">
                        <span />
                        THE WORLD IS STILL FULL OF WONDER
                      </span>
                      <h2>
                        Go somewhere
                        <br />
                        that <em>stays with you.</em>
                      </h2>
                      <p>
                        The places. The people. The unexpected little moments.
                        <br className="desktop-break" />
                        Let’s make a journey that feels like you.
                      </p>
                      <button
                        className="button primary"
                        onClick={() => create()}
                      >
                        Find my next adventure
                        <ArrowUpRight size={18} />
                      </button>
                    </div>
                    <button
                      className="hero-location glass"
                      onClick={() => setDialog(destinations[2])}
                    >
                      <MapPin size={19} />
                      <span>
                        A quieter side of Kyoto
                        <small>34° 59′ N · 135° 47′ E</small>
                      </span>
                      <ArrowUpRight size={17} />
                    </button>
                    <div className="hero-index">
                      <span>JP</span> / KYOTO
                      <i />
                    </div>
                  </section>
                  <section className="prompt-card glass">
                    <div className="prompt-title">
                      <span className="spark-icon">
                        <Sparkles size={18} />
                      </span>
                      <div>
                        <h3>A great trip starts with a little daydream.</h3>
                        <p>
                          Tell Ari what you have in mind. We’ll find your way.
                        </p>
                      </div>
                      <span className="ai-label">YOUR AI CO-PILOT</span>
                    </div>
                    <form
                      onSubmit={(e) => {
                        e.preventDefault();
                        create(draft);
                      }}
                    >
                      <input
                        aria-label="Describe your dream trip"
                        placeholder="A week in Japan, hidden cafés, a little adventure…"
                        value={draft}
                        onChange={(e) => setDraft(e.target.value)}
                        maxLength={600}
                      />
                      <button className="button primary" type="submit">
                        Make it happen
                        <ArrowRight size={17} />
                      </button>
                    </form>
                    <div className="prompt-bottom">
                      <span>Try a little inspiration</span>
                      {[
                        "3 days in Kyoto",
                        "A Tokyo food adventure",
                        "A day in Kuala Lumpur",
                      ].map((t) => (
                        <button key={t} onClick={() => create(t)}>
                          {t}
                          <ArrowUpRight size={12} />
                        </button>
                      ))}
                    </div>
                  </section>
                </div>
                <aside className="discovery-aside">
                  <section className="companion-card glass">
                    <div className="section-top">
                      <span className="eyebrow">
                        <Sparkles size={14} /> A LITTLE HELP, A LOT OF HEART
                      </span>
                      <span className="tiny-dot" />
                    </div>
                    <div className="companion-scene">
                      {scene}
                      <span className="floating-note note-one">
                        <Compass size={14} />
                        Your curiosity, my compass.
                      </span>
                      <span className="floating-star">✧</span>
                    </div>
                    <div className="companion-copy">
                      <h2>
                        Meet Ari.
                        <br />
                        <em>Your plus-one to anywhere.</em>
                      </h2>
                      <p>
                        Big ideas, little details, unexpected detours.
                        <br />
                        I’m here for all of it.
                      </p>
                      <button
                        className="button secondary"
                        onClick={() => setDialog("assistant")}
                      >
                        <MessageCircle size={16} />
                        Say hello to Ari
                        <ArrowUpRight size={16} />
                      </button>
                    </div>
                  </section>
                  <button
                    className="continue-card glass"
                    onClick={() => go("trips")}
                  >
                    <div className="continue-image">
                      <img
                        src={photos.tokyo}
                        alt="Tokyo city skyline"
                        loading="lazy"
                      />
                      <span className="pill">
                        {trip.demo ? "SAMPLE JOURNEY" : "YOUR JOURNEY"}
                      </span>
                    </div>
                    <div className="continue-body">
                      <span className="eyebrow">
                        PICK UP WHERE YOU LEFT OFF
                      </span>
                      <h3>
                        {trip.cities[0].replaceAll("-", " ")}
                        <ArrowUpRight size={19} />
                      </h3>
                      <p>
                        <CalendarDays size={13} />
                        {dayLabel(trip.start_date)}
                        <span>·</span>
                        {trip.days.length} days<span>·</span>
                        {trip.intent.crew_size} travelers
                      </p>
                    </div>
                  </button>
                </aside>
              </div>
              <section className="destinations-section">
                <SectionHeader
                  eyebrow="FOLLOW THAT FEELING"
                  title="A place for every kind of you."
                  action={
                    <button
                      className="text-button"
                      onClick={() => {
                        setFilter("All");
                        document
                          .getElementById("destinations")
                          ?.scrollIntoView({
                            behavior: motion ? "smooth" : "instant",
                          });
                      }}
                    >
                      Explore all destinations
                      <ArrowRight size={16} />
                    </button>
                  }
                />
                <div className="filter-row">
                  <div className="filter-chips">
                    {[
                      "For you",
                      "Cities",
                      "Nature",
                      "Culture",
                      "Food",
                      "Beaches",
                    ].map((f) => (
                      <button
                        key={f}
                        className={filter === f ? "selected" : ""}
                        aria-pressed={filter === f}
                        onClick={() => setFilter(f)}
                      >
                        {f === "For you" && <Sparkles size={14} />} {f}
                      </button>
                    ))}
                  </div>
                  <label className="search-field">
                    <Search size={16} />
                    <input
                      aria-label="Search destinations"
                      value={query}
                      onChange={(e) => setQuery(e.target.value)}
                      placeholder="Find your somewhere"
                    />
                    {query && (
                      <button
                        aria-label="Clear search"
                        onClick={() => setQuery("")}
                      >
                        <X size={14} />
                      </button>
                    )}
                  </label>
                </div>
                <div className="destination-grid" id="destinations">
                  {filtered
                    .slice(0, filter === "For you" ? 3 : undefined)
                    .map((d) => (
                      <DestinationCard
                        key={d.id}
                        destination={d}
                        saved={saved.includes(d.id)}
                        toggleSave={() => toggleSave(d.id)}
                        open={() => setDialog(d)}
                      />
                    ))}
                </div>
                {!filtered.length && (
                  <Empty
                    icon={<Search />}
                    title="Somewhere else in mind?"
                    text="Try a city or country name, or choose another collection."
                    action={
                      <button
                        className="button secondary"
                        onClick={() => {
                          setQuery("");
                          setFilter("All");
                        }}
                      >
                        Show all destinations
                      </button>
                    }
                  />
                )}
              </section>
              <div className="discovery-footer">
                <span>
                  <ShieldCheck size={16} />
                  Your pace. Your people. Your kind of trip.
                </span>
                <span>
                  A world of possibility. <em>One journey at a time.</em>
                  <Compass size={19} />
                </span>
              </div>
            </>
          )}
          {(page === "trips" || page === "map" || page === "live") && (
            <>
              <SectionHeader
                eyebrow={
                  trip.demo ? "EXPLORE A SAMPLE JOURNEY" : "YOUR NEXT CHAPTER"
                }
                title={
                  page === "live"
                    ? "Be here. We’ll handle the next step."
                    : trip.title
                }
                action={
                  <>
                    <button
                      className="button secondary"
                      aria-label="Download itinerary"
                      onClick={download}
                    >
                      <Download size={16} />
                      <span>Download</span>
                    </button>
                    <button className="button primary" onClick={() => create()}>
                      <Plus size={17} />
                      New trip
                    </button>
                  </>
                }
              />
              <div className="trip-meta">
                <span>
                  <MapPin size={15} />
                  {trip.cities.join(" · ").replaceAll("-", " ")}
                </span>
                <span>
                  <CalendarDays size={15} />
                  {dayLabel(trip.start_date)} · {trip.days.length} days
                </span>
                <span>
                  <Users size={15} />
                  {trip.intent.crew_size} travelers
                </span>
                {trip.demo && (
                  <span className="pill sample">
                    Sample itinerary · estimated costs
                  </span>
                )}
              </div>
              {page === "live" && currentDay && (
                <LiveBrief
                  key={`${trip.id}-${currentDay.index}-${currentDay.items.find((s) => s.status !== "done")?.id}`}
                  trip={trip}
                  day={currentDay}
                />
              )}
              <div className="trip-tabs">
                <div className="day-tabs">
                  {trip.days.map((d, i) => (
                    <button
                      key={d.index}
                      onClick={() => chooseDay(i)}
                      className={day === i ? "active" : ""}
                    >
                      <strong>Day {i + 1}</strong>
                      <span>{dayLabel(d.date)}</span>
                    </button>
                  ))}
                </div>
                <button
                  className="text-button rescue-link"
                  onClick={() => setDialog("rescue")}
                >
                  <CloudRain size={17} />
                  Rescue my day
                  <ArrowUpRight size={15} />
                </button>
              </div>
              <div
                className={`trip-workspace ${page === "map" ? "map-priority" : ""}`}
              >
                <section className="itinerary-panel glass">
                  <div className="itinerary-heading">
                    <span className="eyebrow">{currentDay?.zone}</span>
                    <h2>{currentDay?.title}</h2>
                    <p>
                      {items.length} stops<span>·</span>A little room for the
                      unexpected
                    </p>
                  </div>
                  <div className="stop-list">
                    {items.map((stop, index) => (
                      <div className="stop-wrapper" key={stop.id}>
                        {stop.leg && (
                          <div className="leg">
                            <Footprints size={12} />
                            {stop.leg.minutes} min{" "}
                            {stop.leg.mode === "walk" ? "walk" : "transit"}
                            <span>estimated</span>
                          </div>
                        )}
                        <button
                          className={`stop-card ${selected === stop.id ? "selected" : ""}`}
                          onClick={() =>
                            setSelected(selected === stop.id ? null : stop.id)
                          }
                        >
                          <span className="stop-number">
                            {stop.status === "done" ? (
                              <Check size={13} />
                            ) : (
                              index + 1
                            )}
                          </span>
                          <img
                            src={
                              stop.image ??
                              photos[
                                stop.category === "food" ? "food" : "kyoto"
                              ]
                            }
                            alt=""
                            loading="lazy"
                          />
                          <span className="stop-info">
                            <small>
                              {stop.start.slice(11, 16)}{" "}
                              <span>· {stop.category}</span>
                            </small>
                            <strong>{stop.name}</strong>
                            <span>
                              <Clock size={12} />
                              {stop.duration_min} min
                              {stop.cost && (
                                <>
                                  {" "}
                                  ·{" "}
                                  {money(
                                    fromMinor(stop.cost),
                                    stop.cost.currency,
                                  )}
                                </>
                              )}
                            </span>
                          </span>
                          <ChevronRight size={16} />
                        </button>
                        {selected === stop.id && (
                          <div className="stop-expanded">
                            <p>{stop.reason}</p>
                            <a
                              className="text-button"
                              href={`https://www.google.com/maps/dir/?api=1&destination=${stop.lat},${stop.lon}&travelmode=walking`}
                              target="_blank"
                              rel="noreferrer"
                            >
                              Get directions
                              <ArrowUpRight size={14} />
                            </a>
                            <button
                              className="text-button"
                              onClick={async () => {
                                try {
                                  if (trip.demo) {
                                    saveTrip({
                                      ...trip,
                                      days: trip.days.map((d) => ({
                                        ...d,
                                        items: d.items.map((s) =>
                                          s.id === stop.id
                                            ? { ...s, status: "done" }
                                            : s,
                                        ),
                                      })),
                                    });
                                  } else {
                                    saveTrip(
                                      await api<Trip>(
                                        `/v1/trips/${trip.id}/items/${stop.id}`,
                                        { action: "done" },
                                      ),
                                    );
                                  }
                                  notify(
                                    "One more memory made. Stop completed.",
                                  );
                                } catch (e) {
                                  notify(errorMessage(e));
                                }
                              }}
                            >
                              <Check size={14} />
                              Mark visited
                            </button>
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                  <div className="itinerary-end">
                    <span>✧</span>Good journeys leave a little room to wander.
                  </div>
                </section>
                <div className="map-panel">
                  {map}
                  <div className="map-under">
                    <span>
                      <Layers size={14} />A new perspective on your plans
                    </span>
                    <button
                      className="text-button"
                      onClick={() => setDialog("assistant")}
                    >
                      Ask Ari about this day
                      <ArrowUpRight size={15} />
                    </button>
                  </div>
                </div>
              </div>
            </>
          )}
          {page === "saved" && (
            <>
              <SectionHeader
                eyebrow="KEEP THE PLACES THAT CALL TO YOU"
                title="Your someday starts here."
                action={
                  <span className="pill">{saved.length} saved places</span>
                }
              />
              {saved.length ? (
                <div className="destination-grid saved-grid">
                  {destinations
                    .filter((d) => saved.includes(d.id))
                    .map((d) => (
                      <DestinationCard
                        key={d.id}
                        destination={d}
                        saved
                        toggleSave={() => toggleSave(d.id)}
                        open={() => setDialog(d)}
                      />
                    ))}
                </div>
              ) : (
                <Empty
                  icon={<Bookmark />}
                  title="A little collection of possibility."
                  text="Save the places that spark something. They’ll be right here when you’re ready to go."
                  action={
                    <button
                      className="button primary"
                      onClick={() => go("explore")}
                    >
                      Find some inspiration
                      <ArrowRight size={16} />
                    </button>
                  }
                />
              )}
            </>
          )}
          {page === "budget" && (
            <BudgetPage
              trip={trip}
              expenses={expenses}
              openExpense={() => setDialog("expense")}
            />
          )}
          {page === "crew" && <CrewPage trip={trip} notify={notify} />}
          {page === "book" && <BookingPage trip={trip} />}
          {page === "lens" && (
            <ReceiptLens
              trip={trip}
              onSaved={(e) => {
                const next = [...expenses, e];
                setExpenses(next);
                writeLocal("arivo.expenses." + trip.id, next);
                notify("Receipt added to your trip budget.");
              }}
            />
          )}
          {page === "settings" && (
            <>
              <SectionHeader
                eyebrow="MAKE YOURSELF AT HOME"
                title="A little more you."
              />
              <div className="settings-grid">
                <section className="glass settings-panel">
                  <h2>The way you experience Arivo</h2>
                  <Setting
                    label="Motion & 3D animation"
                    detail="A little life in your journey. Turn off for a quieter experience."
                    checked={motion}
                    onChange={() => setMotion(!motion)}
                  />
                  <div className="setting">
                    <div>
                      <strong>Offline itinerary</strong>
                      <p>
                        Your current trip is saved on this device. Map tiles
                        require a connection.
                      </p>
                    </div>
                    <button
                      className="button secondary"
                      aria-label="Download itinerary"
                      onClick={download}
                    >
                      <ArrowDownToLine size={16} />
                      Download
                    </button>
                  </div>
                  <div className="setting">
                    <div>
                      <strong>Your saved places</strong>
                      <p>{saved.length} places in your personal collection.</p>
                    </div>
                    <button className="text-button" onClick={() => go("saved")}>
                      View collection
                      <ArrowRight size={16} />
                    </button>
                  </div>
                </section>
                <section className="glass settings-panel">
                  <ShieldCheck className="large-icon" />
                  <h2>Your journey. Your data.</h2>
                  <p>
                    Trip plans, saved places, and preferences stay in this
                    browser. Requests to plan or replan a trip go to your
                    configured travel service. Nothing is booked or purchased by
                    Ari.
                  </p>
                  <p>
                    Maps load from{" "}
                    {import.meta.env.VITE_MAPBOX_TOKEN
                      ? "Mapbox"
                      : "OpenFreeMap"}
                    . Destination photography loads from Unsplash.
                  </p>
                  <button
                    className="text-button"
                    onClick={() => setDialog("about")}
                  >
                    Credits & details
                    <ArrowUpRight size={16} />
                  </button>
                </section>
              </div>
            </>
          )}
        </main>
      </div>
      <button
        className="floating-ari"
        aria-label="Chat with Ari"
        onClick={() => setDialog("assistant")}
      >
        <img src="/mascot/poster_idle.webp" alt="" />
        <span>Ask Ari</span>
        <Sparkles size={15} />
      </button>
      <nav className="mobile-nav" aria-label="Mobile navigation">
        {[nav[0], nav[1], nav[2], nav[3]].map((n) => (
          <a
            href={`#${n.id}`}
            key={n.id}
            className={page === n.id ? "active" : ""}
          >
            <n.icon size={20} />
            <span>
              {n.label.replace(" places", "").replace(" explorer", "")}
            </span>
          </a>
        ))}
      </nav>
      {toast && (
        <div className="toast glass" role="status">
          <Check size={17} />
          {toast}
          <button
            aria-label="Dismiss notification"
            onClick={() => setToast("")}
          >
            <X size={15} />
          </button>
        </div>
      )}
      {dialog && (
        <Modal
          title={
            typeof dialog === "object"
              ? dialog.name
              : {
                  create: "A new story starts here.",
                  rescue: "A change of plans. Still a great day.",
                  assistant: "Ari, your travel companion",
                  expense: "Keep your budget in the picture.",
                  notifications: "A little travel update",
                  about: "A world of possibility.",
                }[dialog]
          }
          close={() => setDialog(null)}
          wide={dialog === "assistant" || dialog === "rescue"}
        >
          {typeof dialog === "object" && (
            <>
              <img
                className="destination-detail-image"
                src={dialog.image}
                alt={`${dialog.name}, ${dialog.country}`}
              />
              <div className="detail-location">
                <MapPin size={16} />
                {dialog.country}
                <span className="pill">{dialog.category}</span>
              </div>
              <h3 className="serif">{dialog.line}</h3>
              <p className="detail-description">{dialog.text}</p>
              <div className="dialog-actions">
                <button
                  className="button secondary"
                  onClick={() => toggleSave(dialog.id)}
                >
                  <Bookmark
                    size={16}
                    fill={saved.includes(dialog.id) ? "currentColor" : "none"}
                  />
                  {saved.includes(dialog.id)
                    ? "Saved for later"
                    : "Save for later"}
                </button>
                {dialog.supported ? (
                  <button
                    className="button primary"
                    onClick={() =>
                      create(
                        `3 days in ${dialog.name}, local food, culture and time to wander`,
                      )
                    }
                  >
                    Plan a trip here
                    <ArrowRight size={16} />
                  </button>
                ) : (
                  <span className="muted">Planning coverage coming later</span>
                )}
              </div>
            </>
          )}
          {dialog === "create" && (
            <CreateTrip
              initial={draft}
              onCreated={(t) => {
                saveTrip(t);
                setDay(0);
                setDialog(null);
                go("trips");
                notify("Your next chapter is ready.");
              }}
              sample={() => {
                saveTrip(structuredClone(sampleTrip));
                setDay(0);
                setDialog(null);
                go("trips");
              }}
            />
          )}
          {dialog === "rescue" && (
            <Rescue
              trip={trip}
              day={day}
              apply={(t) => {
                saveTrip(t);
                setDialog(null);
                notify("Your new plan is ready. A good day, reimagined.");
              }}
            />
          )}
          {dialog === "assistant" && (
            <Assistant
              trip={trip}
              motion={motion}
              initial={guideInput}
              onInitialUsed={() => setGuideInput("")}
              create={create}
              rescue={() => setDialog("rescue")}
              applyTrip={saveTrip}
            />
          )}
          {dialog === "expense" && (
            <ExpenseForm
              trip={trip}
              save={(e) => {
                const next = [...expenses, e];
                setExpenses(next);
                writeLocal("arivo.expenses." + trip.id, next);
                setDialog(null);
                notify("Expense added to your trip budget.");
              }}
            />
          )}
          {dialog === "notifications" && (
            <div className="notification-content">
              <span className="notification-symbol">
                <Check size={26} />
              </span>
              <h3>You’re all caught up.</h3>
              <p>
                {trip.demo
                  ? "You’re exploring a sample journey. Create a trip when you’re ready to make it yours."
                  : "Your trip is saved on this device and ready to explore."}
              </p>
              <button
                className="button primary"
                onClick={() => {
                  setDialog(null);
                  go("trips");
                }}
              >
                Take me to my trip
                <ArrowRight size={16} />
              </button>
            </div>
          )}
          {dialog === "about" && (
            <div className="about-content">
              <Compass size={38} />
              <p>
                Arivo is a travel space for thoughtful plans, shared
                discoveries, and a little room for the unexpected.
              </p>
              <p>
                Interactive 3D by Three.js. Maps by Mapbox when configured, or
                MapLibre with OpenFreeMap / OpenMapTiles and © OpenStreetMap
                contributors. Photos from Unsplash are destination inspiration;
                itinerary thumbnails are illustrative.
              </p>
              <p>
                Ari is adapted from{" "}
                <a
                  href="https://sketchfab.com/3d-models/miibot-3d-model-7606b66321934033a5dcfecf0f7925e5"
                  target="_blank"
                  rel="noreferrer"
                >
                  Miibot by itsmejhade
                </a>
                , licensed{" "}
                <a
                  href="https://creativecommons.org/licenses/by/4.0/"
                  target="_blank"
                  rel="noreferrer"
                >
                  CC BY 4.0
                </a>
                , with custom travel gear and animation.
              </p>
              <p>
                Sample itineraries and costs are illustrative. Real planning
                uses the existing Arivo API and its source-labelled place data.
                Map lines connect itinerary stops and are not navigation routes.
              </p>
            </div>
          )}
        </Modal>
      )}
    </div>
  );
}

function SectionHeader({
  eyebrow,
  title,
  action,
}: {
  eyebrow: string;
  title: string;
  action?: ReactNode;
}) {
  return (
    <div className="section-header">
      <div>
        <span className="eyebrow">{eyebrow}</span>
        <h1>{title}</h1>
      </div>
      {action && <div className="section-actions">{action}</div>}
    </div>
  );
}
function DestinationCard({
  destination: d,
  saved,
  toggleSave,
  open,
}: {
  destination: Destination;
  saved: boolean;
  toggleSave: () => void;
  open: () => void;
}) {
  return (
    <article className="destination-card">
      <img src={d.image} alt={`${d.name}, ${d.country}`} loading="lazy" />
      <div className="destination-shade" />
      <button
        className={`save-button glass ${saved ? "is-saved" : ""}`}
        aria-label={`${saved ? "Unsave" : "Save"} ${d.name}`}
        aria-pressed={saved}
        onClick={toggleSave}
      >
        <Bookmark size={17} fill={saved ? "currentColor" : "none"} />
      </button>
      <button className="destination-content" onClick={open}>
        <span className="destination-tag" style={{ color: d.color }}>
          {d.tag}
        </span>
        <h2>
          {d.name}
          <span>{d.country}</span>
        </h2>
        <div>
          <p>{d.line}</p>
          <span className="circle-arrow">
            <ArrowUpRight size={19} />
          </span>
        </div>
      </button>
    </article>
  );
}
function Empty({
  icon,
  title,
  text,
  action,
}: {
  icon: ReactNode;
  title: string;
  text: string;
  action?: ReactNode;
}) {
  return (
    <div className="empty-state glass">
      <span className="empty-icon">{icon}</span>
      <h2>{title}</h2>
      <p>{text}</p>
      {action}
    </div>
  );
}
function Setting({
  label,
  detail,
  checked,
  onChange,
}: {
  label: string;
  detail: string;
  checked: boolean;
  onChange: () => void;
}) {
  return (
    <div className="setting">
      <div>
        <strong>{label}</strong>
        <p>{detail}</p>
      </div>
      <button
        className={`switch ${checked ? "on" : ""}`}
        role="switch"
        aria-label={label}
        aria-checked={checked}
        onClick={onChange}
      >
        <span />
      </button>
    </div>
  );
}
function errorMessage(e: unknown) {
  return e instanceof Error
    ? e.message
    : "Something went wrong. Please try again.";
}

function Modal({
  title,
  close,
  wide,
  children,
}: {
  title: string;
  close: () => void;
  wide?: boolean;
  children: ReactNode;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const active = document.activeElement as HTMLElement | null;
    ref.current?.showModal();
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = "";
      active?.focus();
    };
  }, []);
  return (
    <dialog
      ref={ref}
      className={`modal ${wide ? "wide" : ""}`}
      onCancel={(e) => {
        e.preventDefault();
        close();
      }}
      onClick={(e) => {
        if (e.target === ref.current) {
          const r = ref.current!.getBoundingClientRect();
          if (
            e.clientX < r.left ||
            e.clientX > r.right ||
            e.clientY < r.top ||
            e.clientY > r.bottom
          )
            close();
        }
      }}
      aria-labelledby="dialog-title"
    >
      <div className="modal-heading">
        <span className="eyebrow">
          <Compass size={15} /> A LITTLE ARIVO MAGIC
        </span>
        <button
          className="icon-button"
          aria-label="Close dialog"
          onClick={close}
        >
          <X size={20} />
        </button>
      </div>
      <h2 id="dialog-title">{title}</h2>
      {children}
    </dialog>
  );
}

function CreateTrip({
  initial,
  onCreated,
  sample,
}: {
  initial: string;
  onCreated: (trip: Trip) => void;
  sample: () => void;
}) {
  const [text, setText] = useState(initial),
    [crew, setCrew] = useState("couple"),
    [days, setDays] = useState(3),
    [date, setDate] = useState(
      new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10),
    ),
    [budget, setBudget] = useState(1500),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const controller = useRef<AbortController | null>(null);
  useEffect(() => () => controller.current?.abort(), []);
  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    controller.current = new AbortController();
    try {
      const r = await api<{
        status: string;
        trip: Trip;
        question?: { text: string };
        error?: { message: string; supported?: string[] };
      }>(
        "/v1/trips",
        {
          text,
          quick: {
            days,
            start_date: date,
            crew_type: crew,
            crew_size: crew === "solo" ? 1 : crew === "couple" ? 2 : 4,
            budget_amount: budget,
            budget_currency: "USD",
          },
        },
        controller.current.signal,
      );
      if (r.status === "ok") onCreated(r.trip);
      else
        setError(
          r.question?.text ??
            r.error?.message ??
            "Tell Ari a little more about your destination.",
        );
    } catch (e) {
      if (!controller.current.signal.aborted) setError(errorMessage(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <form className="trip-form" onSubmit={submit}>
      <p className="muted">
        Somewhere new. Something you love. Tell us what a good trip feels like.
      </p>
      <label>
        Your little daydream
        <textarea
          required
          minLength={3}
          maxLength={600}
          placeholder="Three days in Kyoto. Great food, quiet gardens and a little adventure…"
          value={text}
          onChange={(e) => setText(e.target.value)}
          autoFocus
        />
      </label>
      <div className="form-grid">
        <label>
          <CalendarDays size={14} />
          Starting on
          <input
            type="date"
            required
            min={new Date().toISOString().slice(0, 10)}
            value={date}
            onChange={(e) => setDate(e.target.value)}
          />
        </label>
        <label>
          <Clock size={14} />
          Days away
          <input
            type="number"
            required
            min={1}
            max={30}
            value={days}
            onChange={(e) => setDays(Number(e.target.value))}
          />
        </label>
        <label>
          <Wallet size={14} />
          Budget per traveler (USD)
          <input
            type="number"
            min={1}
            max={1000000}
            required
            value={budget}
            onChange={(e) => setBudget(Number(e.target.value))}
          />
        </label>
      </div>
      <fieldset>
        <legend>Your travel company</legend>
        <div className="crew-options">
          {["solo", "couple", "friends", "family"].map((c) => (
            <button
              key={c}
              type="button"
              aria-pressed={crew === c}
              className={crew === c ? "selected" : ""}
              onClick={() => setCrew(c)}
            >
              <Users size={18} />
              {c}
            </button>
          ))}
        </div>
      </fieldset>
      <span className="form-help">
        <MapPin size={13} />
        Verified planning is available in Tokyo, Kyoto, and Kuala Lumpur.
      </span>
      {error && (
        <p className="inline-error" role="alert">
          {error}
        </p>
      )}
      <button className="button primary full" disabled={busy}>
        {busy ? (
          <>
            <LoaderCircle className="spin" size={17} />
            Finding your way…
          </>
        ) : (
          <>
            Bring my trip to life
            <Sparkles size={17} />
          </>
        )}
      </button>
      <button
        type="button"
        className="text-button full"
        disabled={busy}
        onClick={sample}
      >
        Just looking? Explore the sample Tokyo journey
        <ArrowRight size={15} />
      </button>
    </form>
  );
}

function Rescue({
  trip,
  day,
  apply,
}: {
  trip: Trip;
  day: number;
  apply: (t: Trip) => void;
}) {
  const [trigger, setTrigger] = useState("rain"),
    [change, setChange] = useState<Change | null>(null),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  async function propose() {
    setBusy(true);
    setError("");
    try {
      if (trip.demo) {
        const old = trip.days[day].items;
        const removed =
          trigger === "rain" ? old.filter((s) => !s.indoor) : old.slice(-2);
        const kept = old.filter((s) => !removed.includes(s));
        setChange({
          id: "sample-change",
          day_index: day,
          explanation:
            trigger === "rain"
              ? "A sample indoor alternative. Outdoor stops are removed; indoor experiences stay in the plan."
              : "A sample slower day. The final two stops are removed to leave more time to rest.",
          kept,
          moved: [],
          removed,
          added: [],
          new_items: kept,
        });
      } else {
        const r = await api<{
          status: string;
          change: Change;
          question?: string;
        }>(`/v1/trips/${trip.id}/rescue`, {
          trigger,
          day_index: day,
          now: `${trip.days[day].date}T08:00:00`,
        });
        if (r.status === "proposed") setChange(r.change);
        else setError(r.question ?? "A little more detail is needed.");
      }
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setBusy(false);
    }
  }
  async function confirm() {
    if (!change) return;
    setBusy(true);
    try {
      if (trip.demo)
        apply({
          ...trip,
          days: trip.days.map((d, i) =>
            i === day ? { ...d, items: change.new_items } : d,
          ),
        });
      else {
        const r = await api<{ trip: Trip }>(
          `/v1/trips/${trip.id}/changes/${change.id}/apply`,
          {},
        );
        apply(r.trip);
      }
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="rescue-content">
      <p className="muted">
        Life happens. Let’s make a little space for it. You’ll review every
        change before it becomes your plan.
      </p>
      {!change ? (
        <>
          <div className="rescue-options">
            {[
              {
                id: "rain",
                icon: CloudRain,
                title: "Rain on the horizon",
                text: "More time indoors, just as much discovery.",
              },
              {
                id: "fatigue",
                icon: Leaf,
                title: "A slower kind of day",
                text: "Fewer stops. A little room to breathe.",
              },
            ].map((t) => (
              <button
                key={t.id}
                className={`glass ${trigger === t.id ? "selected" : ""}`}
                onClick={() => setTrigger(t.id)}
              >
                <t.icon size={26} />
                <strong>{t.title}</strong>
                <span>{t.text}</span>
              </button>
            ))}
          </div>
          <button
            className="button primary full"
            disabled={busy}
            onClick={propose}
          >
            {busy ? (
              <LoaderCircle className="spin" size={17} />
            ) : (
              <Sparkles size={17} />
            )}
            Find a fresh plan
          </button>
        </>
      ) : (
        <>
          <p className="change-explanation">{change.explanation}</p>
          {trip.demo && (
            <span className="pill sample">Sample change · local preview</span>
          )}
          <div className="change-grid">
            {(["kept", "moved", "removed", "added"] as const).map((k) => (
              <section key={k} className={`change-group ${k}`}>
                <h3>
                  {k}
                  <span>{change[k].length}</span>
                </h3>
                {change[k].map((s, i) => (
                  <p key={i}>
                    {k === "removed" ? <X size={13} /> : <Check size={13} />}{" "}
                    {s.name}
                  </p>
                ))}
                {!change[k].length && <p className="muted">No changes</p>}
              </section>
            ))}
          </div>
          <div className="dialog-actions">
            <button
              className="button secondary"
              disabled={busy}
              onClick={() => setChange(null)}
            >
              Back to options
            </button>
            <button
              className="button primary"
              disabled={busy}
              onClick={confirm}
            >
              {busy ? (
                <LoaderCircle className="spin" size={17} />
              ) : (
                <Check size={17} />
              )}
              Use this plan
            </button>
          </div>
        </>
      )}
      {error && (
        <p className="inline-error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}

function Assistant({
  trip,
  motion,
  initial,
  onInitialUsed,
  create,
  rescue,
  applyTrip,
}: {
  trip: Trip;
  motion: boolean;
  initial: string;
  onInitialUsed: () => void;
  create: (s: string) => void;
  rescue: () => void;
  applyTrip: (t: Trip) => void;
}) {
  const [input, setInput] = useState(initial),
    [messages, setMessages] = useState<{ role: string; text: string }[]>([
      {
        role: "ari",
        text: trip.demo
          ? "Hi, I’m Ari. A good trip leaves a little room for surprise. You’re exploring a sample journey — ask me about the plan, or let’s create one of your own."
          : "Hi, I’m Ari. I have your itinerary right here. Ask me what’s next, find a bite nearby, or tell me what’s changed.",
      },
    ]),
    [busy, setBusy] = useState(false),
    [proposal, setProposal] = useState<GuideProposal | null>(null),
    [cards, setCards] = useState<GuideCard[]>([]);
  const scroll = useRef<HTMLDivElement>(null);
  useEffect(() => {
    onInitialUsed();
  }, []);
  useEffect(() => {
    scroll.current?.scrollTo({
      top: scroll.current.scrollHeight,
      behavior: motion ? "smooth" : "instant",
    });
  }, [messages, busy, motion]);
  async function ask(text: string) {
    if (!text.trim() || busy) return;
    setMessages((m) => [...m, { role: "you", text }]);
    setInput("");
    setBusy(true);
    try {
      if (trip.demo) {
        setMessages((m) => [
          ...m,
          {
            role: "ari",
            text: /budget|cost|spent/i.test(text)
              ? `The sample trip has a ${money(fromMinor(trip.budget!.total), trip.currency)} budget. Head to Trip budget to add your own expenses. These are sample planning figures, not live prices.`
              : /next|plan|stop/i.test(text)
                ? `Day one explores ${trip.days[0].zone}, starting at ${trip.days[0].items[0]?.name ?? "a free morning"}. Select a stop in My trips to see the plan and open directions.`
                : /rain|tired|change/i.test(text)
                  ? "A change of plans can still be a good day. Use “Rescue my day” below to review an alternative before applying it."
                  : "I can help you explore this sample plan, check its budget, or start a real trip. Planning is available for Tokyo, Kyoto, and Kuala Lumpur.",
          },
        ]);
      } else {
        const r = await api<{
          reply: string;
          proposals?: GuideProposal[];
          cards?: GuideCard[];
        }>(`/v1/trips/${trip.id}/guide`, { text });
        setMessages((m) => [...m, { role: "ari", text: r.reply }]);
        setProposal(r.proposals?.[0] ?? null);
        setCards(r.cards ?? []);
      }
    } catch (e) {
      setMessages((m) => [...m, { role: "ari", text: errorMessage(e) }]);
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="assistant">
      <div className="assistant-intro">
        <img src="/mascot/poster_idle.webp" alt="Ari" />
        <div>
          <span className="live-dot" />
          <strong>A little help, whenever you need it.</strong>
          <p>
            {trip.demo
              ? "Sample guide · try the journey"
              : "Connected to your trip"}
          </p>
        </div>
      </div>
      <div className="chat-messages" ref={scroll} aria-live="polite">
        {messages.map((m, i) => (
          <div key={i} className={`chat-bubble ${m.role}`}>
            <small>{m.role === "ari" ? "ARI" : "YOU"}</small>
            <p>{m.text}</p>
          </div>
        ))}
        {busy && (
          <div className="chat-bubble ari thinking">
            <LoaderCircle className="spin" size={15} />
            Ari is finding your way…
          </div>
        )}
        <GuideCards cards={cards} />
      </div>
      {proposal && (
        <GuideReview
          proposal={proposal}
          trip={trip}
          apply={applyTrip}
          dismiss={() => setProposal(null)}
        />
      )}
      <div className="chat-suggestions">
        {["What’s next?", "How is my budget?", "Find food nearby"].map((s) => (
          <button key={s} disabled={busy} onClick={() => ask(s)}>
            {s}
          </button>
        ))}
      </div>
      <form
        className="chat-input"
        onSubmit={(e) => {
          e.preventDefault();
          void ask(input);
        }}
      >
        <input
          aria-label="Message Ari"
          value={input}
          maxLength={500}
          onChange={(e) => setInput(e.target.value)}
          placeholder="A little question, a big idea…"
          autoFocus
        />
        <button
          className="button primary"
          disabled={busy || !input.trim()}
          aria-label="Send message"
        >
          <ArrowRight size={19} />
        </button>
      </form>
      <div className="assistant-actions">
        <button className="text-button" onClick={() => create("")}>
          Plan something new
          <Plus size={14} />
        </button>
        <button className="text-button" onClick={rescue}>
          Rescue my day
          <CloudRain size={14} />
        </button>
      </div>
    </div>
  );
}

function BudgetPage({
  trip,
  expenses,
  openExpense,
}: {
  trip: Trip;
  expenses: Expense[];
  openExpense: () => void;
}) {
  const [remote, setRemote] = useState<{
      total: number;
      spent: number;
      reserved: number;
      remaining: number;
      currency: string;
      lines: { category: string; spent: number }[];
    } | null>(null),
    [error, setError] = useState("");
  useEffect(() => {
    if (trip.demo) return;
    const ctrl = new AbortController();
    api<typeof remote>(`/v1/trips/${trip.id}/budget`, undefined, ctrl.signal)
      .then(setRemote)
      .catch((e) => {
        if (!ctrl.signal.aborted) setError(errorMessage(e));
      });
    return () => ctrl.abort();
  }, [trip.id, trip.demo, expenses.length]);
  const total =
      remote?.total ?? (trip.budget ? fromMinor(trip.budget.total) : 0),
    currency = remote?.currency ?? trip.budget?.total.currency ?? trip.currency;
  const spent = remote?.spent ?? expenseTotal(expenses, currency),
    remaining = remote?.remaining ?? total - spent,
    percent = total > 0 ? Math.min(100, (spent / total) * 100) : 0;
  const cats = [
    { name: "food", label: "Food & good company", icon: Utensils },
    { name: "accommodation", label: "A place to stay", icon: Hotel },
    { name: "transport", label: "Getting around", icon: Navigation },
    { name: "activities", label: "Things to remember", icon: Camera },
    { name: "shopping", label: "A little something", icon: Bookmark },
    { name: "other", label: "The unexpected", icon: Sparkles },
  ];
  return (
    <>
      <SectionHeader
        eyebrow="LESS WORRY. MORE WANDERING."
        title="Good memories. A happy budget."
        action={
          <button className="button primary" onClick={openExpense}>
            <Plus size={17} />
            Add an expense
          </button>
        }
      />
      {trip.demo && (
        <p className="context-note">
          Sample trip budget · expenses you add are saved on this device.
        </p>
      )}
      {error && (
        <p className="inline-error" role="alert">
          {error} Showing locally saved figures.
        </p>
      )}
      <div className="budget-grid">
        <section className="budget-main glass">
          <span className="eyebrow">YOUR TRIP, IN THE PICTURE</span>
          <div className="budget-value">
            {money(remaining, currency)}
            <span>
              {remaining >= 0
                ? "left for making memories"
                : "over your planned budget"}
            </span>
          </div>
          <div className="budget-progress">
            <span style={{ width: `${percent}%` }} />
          </div>
          <div className="budget-numbers">
            <div>
              <span>Spent so far</span>
              <strong>{money(spent, currency)}</strong>
            </div>
            <div>
              <span>Trip budget</span>
              <strong>{money(total, currency)}</strong>
            </div>
            <span className="pill">
              {remaining >= 0 ? "Room to explore" : "Time to rebalance"}
            </span>
          </div>
        </section>
        <section className="budget-note glass">
          <Sparkles size={25} />
          <h2>
            Small details.
            <br />
            <em>More peace of mind.</em>
          </h2>
          <p>
            Keep track as you go. A café here, a train ride there — your
            memories deserve more attention than your receipts.
          </p>
        </section>
      </div>
      <div className="budget-lower">
        <section className="glass panel">
          <h2>Where your journey takes you</h2>
          {cats.map((c) => {
            const amount =
              remote?.lines.find((l) => l.category === c.name)?.spent ??
              expenses
                .filter((e) => e.category === c.name && e.currency === currency)
                .reduce((s, e) => s + e.amount, 0);
            return (
              <div className="budget-category" key={c.name}>
                <span className="category-icon">
                  <c.icon size={18} />
                </span>
                <span>
                  {c.label}
                  <i>
                    <b
                      style={{
                        width: `${spent ? Math.min(100, (amount / spent) * 100) : 0}%`,
                      }}
                    />
                  </i>
                </span>
                <strong>{money(amount, currency)}</strong>
              </div>
            );
          })}
        </section>
        <section className="glass panel">
          <h2>The little things add up</h2>
          <p className="muted">Expenses added on this device</p>
          {expenses.length ? (
            expenses
              .slice()
              .reverse()
              .map((e) => (
                <div className="expense-row" key={e.id}>
                  <div>
                    <strong>{e.merchant}</strong>
                    <span>{e.category}</span>
                  </div>
                  <strong>{money(e.amount, e.currency)}</strong>
                </div>
              ))
          ) : (
            <div className="quiet-empty">
              <Wallet size={28} />
              <p>
                No expenses yet.
                <br />
                Start with your first little adventure.
              </p>
            </div>
          )}
          <button className="text-button" onClick={openExpense}>
            Add an expense
            <Plus size={15} />
          </button>
        </section>
      </div>
    </>
  );
}
function ExpenseForm({
  trip,
  save,
}: {
  trip: Trip;
  save: (e: Expense) => void;
}) {
  const [merchant, setMerchant] = useState(""),
    [amount, setAmount] = useState(""),
    [category, setCategory] = useState("food"),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const currency = trip.budget?.total.currency ?? trip.currency;
  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      if (!trip.demo)
        await api(`/v1/trips/${trip.id}/expenses`, {
          amount: Number(amount),
          currency,
          category,
          merchant,
          source: "manual",
        });
      save({
        id: crypto.randomUUID(),
        merchant,
        amount: Number(amount),
        currency,
        category,
      });
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <form className="trip-form" onSubmit={submit}>
      <p className="muted">A small moment, accounted for.</p>
      <label>
        What was it for?
        <input
          required
          maxLength={120}
          placeholder="Coffee and a very good view"
          value={merchant}
          onChange={(e) => setMerchant(e.target.value)}
          autoFocus
        />
      </label>
      <div className="form-grid two">
        <label>
          Amount ({currency})
          <input
            required
            type="number"
            min="0.01"
            max="1000000"
            step="0.01"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.00"
          />
        </label>
        <label>
          Category
          <select
            value={category}
            onChange={(e) => setCategory(e.target.value)}
          >
            {[
              "food",
              "transport",
              "activities",
              "shopping",
              "accommodation",
              "other",
            ].map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </label>
      </div>
      {error && (
        <p className="inline-error" role="alert">
          {error}
        </p>
      )}
      <button className="button primary full" disabled={busy}>
        {busy ? (
          <LoaderCircle className="spin" size={17} />
        ) : (
          <Plus size={17} />
        )}
        Add expense
      </button>
    </form>
  );
}

function CrewPage({
  trip,
  notify,
}: {
  trip: Trip;
  notify: (s: string) => void;
}) {
  const [prefs, setPrefs] = useState<string[]>(() =>
      readLocal("arivo.crew." + trip.id, ["Culture & history", "Local food"]),
    ),
    [busy, setBusy] = useState(false),
    [invite, setInvite] = useState("");
  const interests = [
    { name: "Culture & history", key: "culture", icon: Compass },
    { name: "Local food", key: "food", icon: Utensils },
    { name: "Nature & outdoors", key: "nature", icon: Leaf },
    { name: "A little nightlife", key: "nightlife", icon: Zap },
    { name: "Photo-worthy places", key: "photography", icon: Camera },
    { name: "Time to unwind", key: "relaxation", icon: Sun },
  ];
  async function inviteCrew() {
    if (trip.demo) {
      notify(
        "Create a real trip to invite your crew. Sample trips stay on this device.",
      );
      return;
    }
    setBusy(true);
    try {
      const r = await api<{ link: string }>(`/v1/trips/${trip.id}/invites`, {});
      setInvite(r.link);
    } catch (e) {
      notify(errorMessage(e));
    } finally {
      setBusy(false);
    }
  }
  async function save() {
    setBusy(true);
    try {
      if (!trip.demo)
        await api(`/v1/trips/${trip.id}/crew/prefs`, {
          votes: Object.fromEntries(
            interests.map((i) => [
              i.key,
              prefs.includes(i.name) ? "love" : "maybe",
            ]),
          ),
        });
      writeLocal("arivo.crew." + trip.id, prefs);
      notify("Your travel preferences are saved.");
    } catch (e) {
      notify(errorMessage(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <SectionHeader
        eyebrow="DIFFERENT PEOPLE. ONE BEAUTIFUL JOURNEY."
        title="Better, together."
        action={
          <button
            className="button primary"
            onClick={inviteCrew}
            disabled={busy}
          >
            <Users size={17} />
            Invite your crew
          </button>
        }
      />
      <div className="crew-grid">
        <section className="glass panel crew-people">
          <span className="eyebrow">YOUR TRAVEL PEOPLE</span>
          <div className="crew-orbit">
            <span className="orbit-line" />
            <span className="crew-center">
              <Compass size={35} />
            </span>
            {trip.crew.map((c, i) => (
              <span key={c.user_id} className={`crew-member member-${i % 4}`}>
                <span className="avatar">{c.display_name.charAt(0)}</span>
                <strong>{c.display_name}</strong>
                <small>{c.role}</small>
              </span>
            ))}
          </div>
          <h2>
            Shared plans.
            <br />
            <em>Different perspectives.</em>
          </h2>
          <p className="muted">
            Make space for everyone’s must-dos and happy accidents.
          </p>
          {invite && (
            <label className="invite-link">
              Share this invitation
              <input
                value={invite}
                readOnly
                onFocus={(e) => e.target.select()}
              />
              <button
                className="button secondary"
                onClick={async () => {
                  try {
                    await navigator.clipboard.writeText(invite);
                    notify("Invite link copied.");
                  } catch {
                    notify("Select and copy the invitation link above.");
                  }
                }}
              >
                Copy invitation
              </button>
            </label>
          )}
        </section>
        <section className="glass panel">
          <span className="eyebrow">WHAT MAKES A TRIP YOURS?</span>
          <h2>Follow your own curiosity.</h2>
          <p className="muted">
            Choose the things you’d love to make room for.
          </p>
          <div className="interest-list">
            {interests.map((i) => (
              <button
                key={i.name}
                className={prefs.includes(i.name) ? "selected" : ""}
                aria-pressed={prefs.includes(i.name)}
                onClick={() =>
                  setPrefs((p) =>
                    p.includes(i.name)
                      ? p.filter((n) => n !== i.name)
                      : [...p, i.name],
                  )
                }
              >
                <i.icon size={20} />
                <span>{i.name}</span>
                <span className="interest-check">
                  {prefs.includes(i.name) && <Check size={13} />}
                </span>
              </button>
            ))}
          </div>
          <button
            className="button primary full"
            onClick={save}
            disabled={busy}
          >
            Save my preferences
            <ArrowRight size={16} />
          </button>
        </section>
      </div>
    </>
  );
}

type Offer = {
  offer_id: string;
  title: string;
  subtitle: string;
  price: { amount_minor: number; currency: string };
  location_fit?: number;
  badges: string[];
  sandbox: boolean;
  cancellation_policy: string;
  meta?: { fit_sentence?: string };
};
function BookingPage({ trip }: { trip: Trip }) {
  const [offers, setOffers] = useState<Offer[]>([]),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [type, setType] = useState("stays"),
    [origin, setOrigin] = useState("KUL"),
    [chosen, setChosen] = useState<Offer | null>(null);
  async function search(e: FormEvent) {
    e.preventDefault();
    setError("");
    setOffers([]);
    setBusy(true);
    try {
      if (trip.demo) {
        setError(
          "Create a trip first to search stays and flights connected to your itinerary.",
        );
        return;
      }
      const r = await api<{ offers: Offer[] }>(
        type === "stays"
          ? `/v1/trips/${trip.id}/bookings/search/stays`
          : "/v1/bookings/search/flights",
        type === "stays"
          ? {
              check_in: trip.start_date,
              nights: trip.days.length,
              guests: Math.min(trip.intent.crew_size, 12),
              rooms: 1,
            }
          : {
              origin,
              destination:
                trip.cities[0] === "kuala-lumpur"
                  ? "KUL"
                  : trip.cities[0] === "kyoto"
                    ? "KIX"
                    : "HND",
              depart: trip.start_date,
              adults: Math.min(trip.intent.crew_size, 9),
            },
      );
      setOffers(r.offers);
      if (!r.offers.length)
        setError(
          "No options returned for these dates. Try again a little later.",
        );
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <SectionHeader
        eyebrow="THE LITTLE DETAILS, ALL IN ONE PLACE"
        title="A good place to land."
      />
      <div
        className="booking-banner"
        style={{
          backgroundImage: `linear-gradient(90deg,rgba(3,19,29,.95),rgba(3,19,29,.15)),url(${photos.tokyo})`,
        }}
      >
        <span className="eyebrow">STAY A LITTLE CLOSER TO YOUR JOURNEY</span>
        <h2>
          Your plans.
          <br />
          <em>A place that fits.</em>
        </h2>
        <p>
          Find stays around your itinerary, with a little
          <br />
          less commuting and a little more being there.
        </p>
      </div>
      <form className="booking-search glass" onSubmit={search}>
        <label>
          Looking for
          <select
            value={type}
            onChange={(e) => {
              setType(e.target.value);
              setOffers([]);
            }}
          >
            <option value="stays">A place to stay</option>
            <option value="flights">Flights</option>
          </select>
        </label>
        {type === "flights" && (
          <label>
            From (airport code)
            <input
              minLength={3}
              maxLength={3}
              required
              value={origin}
              onChange={(e) => setOrigin(e.target.value.toUpperCase())}
            />
          </label>
        )}
        <div>
          <span>Your destination</span>
          <strong className="capitalize">
            {trip.cities[0].replaceAll("-", " ")}
          </strong>
        </div>
        <div>
          <span>Starting on</span>
          <strong>{dayLabel(trip.start_date)}</strong>
        </div>
        <button className="button primary" disabled={busy}>
          {busy ? (
            <LoaderCircle size={17} className="spin" />
          ) : (
            <Search size={17} />
          )}
          Find my fit
        </button>
      </form>
      {error && (
        <p className="inline-error" role="alert">
          {error}
        </p>
      )}
      <div className="offers-grid">
        {offers.map((o) => (
          <article key={o.offer_id} className="glass offer-card">
            <Hotel size={25} />
            <span className="pill">
              {o.sandbox ? "SANDBOX OFFER" : "PROVIDER OFFER"}
            </span>
            <h2>{o.title || o.subtitle}</h2>
            <p>{o.meta?.fit_sentence ?? o.subtitle}</p>
            {o.location_fit && (
              <span className="fit">
                <MapPin size={14} />
                {o.location_fit}% location fit
              </span>
            )}
            <strong className="offer-price">
              {money(fromMinor(o.price), o.price.currency)}
              <small>Total quoted price</small>
            </strong>
            <button
              className="button secondary full"
              onClick={() => setChosen(o)}
            >
              Review details
              <ArrowRight size={16} />
            </button>
          </article>
        ))}
      </div>
      {!offers.length && !error && (
        <div className="context-note">
          <ShieldCheck size={16} />
          You choose the stay. You confirm every booking. Ari never spends your
          money.
        </div>
      )}
      {chosen && (
        <Modal
          title={chosen.title || chosen.subtitle}
          close={() => setChosen(null)}
        >
          <Checkout
            offer={chosen}
            tripId={trip.id}
            travelers={trip.intent.crew_size}
          />
        </Modal>
      )}
    </>
  );
}
