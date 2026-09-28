// Arivo design-system components (window.Arivo). React 18. Types are documentation.
export interface ButtonProps { variant?: 'primary' | 'tonal' | 'quiet' | 'danger'; icon?: string; children: string; onClick?: () => void; disabled?: boolean }
export declare function Button(props: ButtonProps): JSX.Element;

export interface ProvenanceTagProps { kind: 'live' | 'est' | 'you'; source?: string; updated?: string }
export declare function ProvenanceTag(props: ProvenanceTagProps): JSX.Element;

export interface StatusChipProps { tone: 'confirmed' | 'pending' | 'failed' | 'cancelled' | 'sandbox' | 'offline' | 'closed' | 'booked'; children?: string }
export declare function StatusChip(props: StatusChipProps): JSX.Element;

export interface StopCardProps { time: string; place: string; duration?: string; leg?: string; price?: string; provenance?: 'live' | 'est' | 'you'; source?: string; reason?: string; status?: 'planned' | 'booked' | 'next' | 'done' | 'closed'; dayColor?: string }
export declare function StopCard(props: StopCardProps): JSX.Element;

export interface TripSpineProps { day: string; title: string; routeColor?: string; stops: Array<StopCardProps & { legAfter?: { mode: 'walk' | 'train' | 'bus' | 'flight'; label: string } }> }
export declare function TripSpine(props: TripSpineProps): JSX.Element;

export interface PulseBadgeProps { score: number; label: string; expanded?: boolean; evidence?: Array<{ name: string; weight: number; value: string }>; facts?: string[]; sources?: number; updated?: string }
export declare function PulseBadge(props: PulseBadgeProps): JSX.Element;

export interface ChangeDiffProps { timeDelta: string; budgetDelta: number; currency: string; groups: { kept?: Item[]; moved?: Item[]; removed?: Item[]; added?: Item[] }  // Item = { name; from?; to?; reason?; detail? } }
export declare function ChangeDiff(props: ChangeDiffProps): JSX.Element;

export interface BudgetGaugeProps { total: number; spent: number; reserved?: number; forecast: number; currency: string }
export declare function BudgetGauge(props: BudgetGaugeProps): JSX.Element;

export interface LocationFitMeterProps { score: number; sentence?: string }
export declare function LocationFitMeter(props: LocationFitMeterProps): JSX.Element;

export interface BoardingPassCardProps { kind: 'flight' | 'stay' | 'bus' | 'rail'; carrier: string; from: string; to: string; depart: string; arrive: string; date: string; reference: string; status?: 'confirmed' | 'pending' | 'failed' | 'cancelled' | 'offline'; sandbox?: boolean; note?: string }
export declare function BoardingPassCard(props: BoardingPassCardProps): JSX.Element;

export interface PriceBreakdownProps { currency: string; lines: Array<{ label: string; amount: number }>; total: number; changedFrom?: number; terms?: string[]; action?: string }
export declare function PriceBreakdown(props: PriceBreakdownProps): JSX.Element;

export interface CrewConstellationProps { members: Array<{ name: string }>; links?: Array<{ a: number; b: number; label?: string; conflict?: boolean }>; balance?: Array<{ name: string; share: number; note?: string }>; label?: string }
export declare function CrewConstellation(props: CrewConstellationProps): JSX.Element;
